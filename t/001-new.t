# -*- perl -*-

# t/001-new.t - check module loading

use Test::More;

BEGIN { use_ok( 'Perl5::Dist::Backcompat' ); }

my $self;

$self = Perl5::Dist::Backcompat->new();
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
        } );
    };
    like($@, qr/Constructor parameter\(s\).+?not valid/,
        "Invalid arguments in hashref supplied to to new()");
}

$self = Perl5::Dist::Backcompat->new();
is($self->{host}, 'dromedary.p5h.org', "Got default value for 'host'");
is($self->{path_to_perls}, '/media/Tux/perls-t/bin', "Got default value for 'path_to_perls'");
done_testing();
