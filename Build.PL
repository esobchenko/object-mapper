use Module::Build;

use strict;

my $build = Module::Build->new(
	module_name => 'Object::Mapper',
	license => 'perl',
	requires => {
		'perl' => '5.6.1',
		'version' => '0.50',
		'Test::More' => '0.47',
		'Class::Accessor' => '0.31',
		'Class::Data::Inheritable' => '0.06',
		'DBM::Deep' => '1.0005',
	},
	dist_author => 'Eugen Sobchenko <ejs@cpan.org>',
	add_to_cleanup => [
		'META.yml', '*.gz',
	],
);

$build->create_build_script;
