use strict;
use Test::More;

$ENV{PERL_FNS_NO_OPT} = 1;
require Filesys::Notify::Simple;

my $fs = Filesys::Notify::Simple->new(["/xxx/nonexistent"]);

eval {
    $SIG{ALRM} = sub { die "Alarm\n" };
    alarm 1;
    $fs->wait(sub {});
};

is $@, "Alarm\n";

done_testing;


