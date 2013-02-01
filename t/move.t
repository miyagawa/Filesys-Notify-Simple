use strict;
use Filesys::Notify::Simple;
use Test::More;
use Test::SharedFork;
use FindBin;

plan tests => 2;

my $w = Filesys::Notify::Simple->new([ "lib", "t" ]);
my $test_file = "$FindBin::Bin/x/move_create.data";
my $test_file_to = "$FindBin::Bin/x/move_create.data.to";

my $pid = fork;
if ($pid == 0) {
    Test::SharedFork->child;
    sleep 3;
    open my $out, ">", $test_file;
    print $out "foo" . time;
    close $out;
    sleep 3;
    rename($test_file => $test_file_to);
} elsif ($pid != 0) {
    Test::SharedFork->parent;
    my $event;
    for (1..2) {
        alarm 10;
        $w->wait(sub { $event = shift }); # create
        like $event->{path}, qr/move_create\.data/;
    }
    unlink $test_file_to;

    waitpid $pid, 0;
} else {
    die $!;
}


