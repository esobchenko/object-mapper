#
# $Id: Mapper.pm 120 2008-04-09 19:23:42Z esobchenko $
package Object::Mapper;

use version; $VERSION = qv('1.0.0');

use strict;
use warnings;

use Carp qw/croak carp/;
use Scalar::Util qw/refaddr blessed weaken/;

use DBM::Deep;
use Cache::Weak;

use base qw/Class::Data::Inheritable Class::Accessor/;

__PACKAGE__->mk_classdata ('file' => "objects.db");
__PACKAGE__->mk_classdata ('auto_update' => 0);

__PACKAGE__->mk_accessors ('id'); # object identity

# Live object meta data (changed attributes, autoupdate switch) stored separately
# and removed automatically on DESTROY(). Object's refaddr is used as a hash key
my %live_objects_meta = ();

sub auto_update {
	my $self = shift;

	if (@_) {
		$live_objects_meta{ refaddr $self }{auto_update} = $_[0];
	}

	my $auto_update = $self->_class->auto_update();

	if ( exists $live_objects_meta{ refaddr $self }{auto_update} ) {
		$auto_update = $live_objects_meta{ refaddr $self }{auto_update};
	}

	return $auto_update;
}

sub is_changed {
	my $self = shift;

	if (@_) {
		return exists $live_objects_meta{ refaddr $self }{changed}{$_[0]};
	}

	return exists $live_objects_meta{ refaddr $self }->{changed};
}

sub changed_attributes {
	my $self = shift;

	my @changed = ();

	if (exists $live_objects_meta{ refaddr $self }->{changed}) {
		@changed = keys %{ $live_objects_meta{ refaddr $self }->{changed} };
	}

	wantarray ? @changed : scalar @changed;
}

# live object cache is used to support uniqueness of objects in memory
sub _cache {
	return Cache::Weak->new( blessed $_[0] ? shift->_class : $_[0] );
}

sub add_to_object_cache {
	my $self = shift;
	$self->_cache->set( $self->id, $self );
}

sub remove_from_object_cache {
	my $self = shift;
	$self->_cache->remove( $self->id );
}

sub retrieve_from_object_cache {
	my ( $class, $id ) = @_;
	croak "calling retrieve_from_object_cache() without specifying object id" unless defined $id;
	return $class->_cache->get( $id );
}

sub is_cached {
	my ( $self, $id ) = @_;

	unless ( blessed $self ) { # invoked as class method
		croak "calling is_cached() as class method withoud specifying object id" unless defined $id;
	} else {
		$id = $self->id();
	}

	return $self->_cache->exists($id);
}

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_); # calling Class::Accessor::new()

	unless ( defined $self->id ) {
		$self->_create(@_); # create object and set it's identity
		croak sprintf (
			"%s object identity still not defined after _create() is invoked",
			$class
		) unless defined $self->id;
	};

	$self->add_to_object_cache;

	return $self;
}

sub set {
	my $self = shift;
	$self->SUPER::set(@_);
	# count how many times attribute changed between updates.
	$live_objects_meta{ refaddr $self }{changed}{$_[0]}++;
	$self->update() if $self->auto_update;
}

sub delete {
	my $self = shift;

	unless (blessed $self) { # invoked as class method
		my $id = shift or croak "calling delete() as class method without specifying object id";
		return $self->retrieve($id)->delete();
	}

	$self->_delete(@_);
}

sub retrieve {
	my ($class, $id) = @_;

	croak "retrieve() invoked without specifying object id" unless $id;

	# return cached copy if available
	return $class->retrieve_cached($id) if $class->is_cached($id);

	my $self = $class->_read($id);

	# acknowledge we've retrieved what we expected to retrieve
	if (my $blessed = blessed $self) {
		croak sprintf (
			"%s object is retrieved by %s::_read() when %s is expected",
			$blessed, $class, $class
		) unless ($blessed eq $class);

		croak sprintf (
			"wrong %s object is retrieved by _read(). (expected id: %s, actual id: %s)",
			$blessed, $id, $self->id
		) if ($id cmp $self->id)
	} else {
		croak sprintf (
			"unblessed reference is retrieved by %s::_read()",
			$class
		);
	}

	$self->add_to_object_cache;
	return $self;
}

sub update {
	my $self = shift;
	$self->_update() if $self->is_changed;
	delete ${ $live_objects_meta{ refaddr $self } }{changed};
	return 1;
}

sub _class () { return blessed shift }

sub DESTROY {
	my $self = shift;
	my @changed = ();

	carp sprintf (
		"%s object destroyed without saving changes of %s",
		$self->_class, join (', ', @changed)
	) if ( @changed = $self->changed_attributes );

	# object's meta is relevent only during the objects life time
	delete $live_objects_meta{ refaddr $self };
}

#
# DBM::Deep is used as a default persistent storage
#

sub _db {
	my $invocator = shift;
	my $class = blessed $invocator ? $invocator->_class : $invocator;
	return DBM::Deep->new( file => $class->file, locking => 1, autoflush => 1 );
}

#
# CRUD procedures
#

sub _create {
	my $self = shift;

	my $db = $self->_db;
	my $class = $self->_class;

	$db->{$class} ||= [];
	# add 1 to length since array index start at 0
	$self->{id} = ( 1 + $db->{$class}->length );
	push @{ $db->{$class} }, $self;
}

sub _update {
	my $self = shift;
	$self->_db->{ $self->_class }[ $self->id - 1 ] = $self;
}

sub _delete {
	my $self = shift;

	delete $self->_db->{ $self->_class }[ $self->id - 1 ];
	delete $self->{id};
}

sub _read {
	my ( $class, $id ) = @_;
	return $class->_db->{$class}[ $id - 1 ];
}

1;

