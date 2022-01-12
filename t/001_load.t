# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 2;

BEGIN { use_ok( 'Perl5::Dist::Backcompat' ); }

my $object = Perl5::Dist::Backcompat->new ();
isa_ok ($object, 'Perl5::Dist::Backcompat');


