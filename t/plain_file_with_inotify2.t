use strict;
use warnings;

use Filesys::Notify::Simple;
use Test::More;
use FindBin;

eval { require Linux::Inotify2 };

plan skip_all => 'Linux::Inotify2 is required to run this test' if $@;

my $test_file = "$FindBin::Bin/x/plain_file_for_inotify2.data";
open my $out, ">", $test_file;
print $out "foo" . time;
close $out;

my $w = Filesys::Notify::Simple->new( [$test_file] );

my $pid = fork;
if ( $pid == 0 ) {
    sleep 3;

    unlink $test_file;

    my $other_file = "$FindBin::Bin/x/bar";
    open $out, ">", $other_file;
    print $out "bar" . time;
    close $out;

    unlink $other_file;

    exit;
}
elsif ( $pid != 0 ) {
    my $event;

    local $SIG{ALRM} = sub { return };
    alarm 10;

    $w->wait( sub { $event = shift } );
    like $event->{path}, qr/plain_file_for_inotify2/,
      'first event is from watched file';

    $w->wait( sub { $event = shift } );
    is $event, undef, 'only one event';

    waitpid $pid, 0;
}
else {
    die $!;
}

done_testing();

