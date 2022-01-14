# -*- perl -*-
# t/001-new.t
use strict;
use warnings;

use Test::More tests =>  8;

BEGIN { use_ok( 'Perl5::Dist::Backcompat' ); }

my $self;

$self = Perl5::Dist::Backcompat->new( { perl_workdir => '/path/to/checkout' } );
isa_ok($self, 'Perl5::Dist::Backcompat');

{
    local $@;
    eval { $self = Perl5::Dist::Backcompat->new([]); };
    like($@, qr/Argument supplied to constructor must be hashref/,
        "Wrong type of argument to new()");
}

{
    local $@;
    eval { $self = Perl5::Dist::Backcompat->new( {
            verbose => 1,
            foo => 2,
            bar => 3,
            perl_workdir => '/some/path',
        } );
    };
    like($@, qr/Constructor parameter\(s\).+?not valid/,
        "Invalid arguments in hashref supplied to to new()");
}

{
    local $@;
    eval { $self = Perl5::Dist::Backcompat->new( {
            verbose => 1,
        } );
    };
    like($@, qr/Must supply value for 'perl_workdir'/,
        "Must supply path to git checkout of Perl 5 core distribution");
}

$self = Perl5::Dist::Backcompat->new( {
    perl_workdir => '/some/path',
    verbose => 1,
} );
is($self->{host}, 'dromedary.p5h.org', "Got default value for 'host'");
is($self->{path_to_perls}, '/media/Tux/perls-t/bin', "Got default value for 'path_to_perls'");
ok($self->{verbose}, 'Selection for verbosity verified');

