package Filesys::Notify::Simple;

use strict;
use 5.008_001;
our $VERSION = '0.13';

use Carp ();
use Cwd;
use constant NO_OPT => $ENV{PERL_FNS_NO_OPT};

sub new {
    my($class, $path) = @_;

    unless (ref $path eq 'ARRAY') {
        Carp::croak('Usage: Filesys::Notify::Simple->new([ $path1, $path2 ])');
    }

    my $self = bless { paths => $path }, $class;
    $self->init;

    $self;
}

sub wait {
    my($self, $cb) = @_;

    $self->{watcher} ||= $self->{watcher_cb}->(@{$self->{paths}});
    $self->{watcher}->($cb);
}

sub init {
    my $self = shift;

    local $@;
    if ($^O eq 'linux' && !NO_OPT && eval { require Linux::Inotify2; 1 }) {
        $self->{watcher_cb} = \&wait_inotify2;
    } elsif ($^O eq 'darwin' && !NO_OPT && eval { require Mac::FSEvents; 1 }) {
        $self->{watcher_cb} = \&wait_fsevents;
    } elsif (($^O eq 'freebsd' || $^O eq 'openbsd') && !NO_OPT && eval { require Filesys::Notify::KQueue; 1 }) {
        $self->{watcher_cb} = \&wait_kqueue;
    } elsif ($^O eq 'MSWin32' && !NO_OPT && eval { require Win32::ChangeNotify; 1 }) {
        $self->{watcher_cb} = mk_wait_win32(0); # Not cygwin
    } elsif ($^O eq 'cygwin' && !NO_OPT && eval { require Win32::ChangeNotify; 1 }) {
        $self->{watcher_cb} = mk_wait_win32(1); # Cygwin
    } else {
        $self->{watcher_cb} = \&wait_timer;
    }
}

sub wait_inotify2 {
    my @path = @_;

    Linux::Inotify2->import;
    my $inotify = Linux::Inotify2->new;

    my $fs = _full_scan(@path);
    for my $path (keys %$fs) {
        $inotify->watch($path, &IN_MODIFY|&IN_CREATE|&IN_DELETE|&IN_DELETE_SELF|&IN_MOVE_SELF|&IN_MOVE)
            or Carp::croak("watch failed: $!");
    }

    return sub {
        my $cb = shift;
        $inotify->blocking(1);
        my @events = $inotify->read;
        $cb->(map { +{ path => $_->fullname } } @events);
    };
}

sub wait_fsevents {
    require IO::Select;
    my @path = @_;

    my $fs = _full_scan(@path);
    my $sel = IO::Select->new;

    my %events;
    for my $path (@path) {
        my $fsevents = Mac::FSEvents->new({ path => $path, latency => 1, file_events => 1 });
        my $fh = $fsevents->watch;
        $sel->add($fh);
        $events{fileno $fh} = $fsevents;
    }

    return sub {
        my $cb = shift;

        my @ready = $sel->can_read;
        my @events;
        for my $fh (@ready) {
            my $fsevents = $events{fileno $fh};
            my %uniq;
            my @path = grep !$uniq{$_}++, map { $_->path } $fsevents->read_events;

            my $new_fs = _full_scan(@path);
            my $old_fs = +{ map { ($_ => $fs->{$_}) } keys %$new_fs };
            _compare_fs($old_fs, $new_fs, sub { push @events, { path => $_[0] } });
            $fs->{$_} = $new_fs->{$_} for keys %$new_fs;
            last if @events;
        }

        $cb->(@events);
    };
}

sub wait_kqueue {
    my @path = @_;

    my $kqueue = Filesys::Notify::KQueue->new(
        path => \@path
    );

    return sub { $kqueue->wait(shift) };
}

sub mk_wait_win32 {
    my ($is_cygwin) = @_;

    return sub {
        my @path = @_;

        my $fs = _full_scan(@path);
        my (@notify, @fskey);
        for my $path (keys %$fs) {
            my $winpath = $is_cygwin ? Cygwin::posix_to_win_path($path) : $path;
            # 0x1b means 'DIR_NAME|FILE_NAME|LAST_WRITE|SIZE' = 2|1|0x10|8
            push @notify, Win32::ChangeNotify->new($winpath, 0, 0x1b);
            push @fskey, $path;
        }

        return sub {
            my $cb = shift;

            my @events;
            while(1) {
                my $idx = Win32::ChangeNotify::wait_any(\@notify);
                Carp::croak("Can't wait notifications, maybe ".scalar(@notify)." directories exceeds limitation.") if ! defined $idx;
                if($idx > 0) {
                    --$idx;
                    my $new_fs = _full_scan($fskey[$idx]);
                    $notify[$idx]->reset;
                    my $old_fs = +{ map { ($_ => $fs->{$_}) } keys %$new_fs };
                    _compare_fs($old_fs, $new_fs, sub { push @events, { path => $_[0] } });
                    $fs->{$_} = $new_fs->{$_} for keys %$new_fs;
                    last if @events; # Actually changed
                }
            }
            $cb->(@events);
        }
    }
}

sub wait_timer {
    my @path = @_;

    my $fs = _full_scan(@path);

    return sub {
        my $cb = shift;
        my @events;
        while (1) {
            sleep 2;
            my $new_fs = _full_scan(@path);
            _compare_fs($fs, $new_fs, sub { push @events, { path => $_[0] } });
            $fs = $new_fs;
            last if @events;
        };
        $cb->(@events);
    };
}

sub _compare_fs {
    my($old, $new, $cb) = @_;

    for my $dir (keys %$old) {
        for my $path (keys %{$old->{$dir}}) {
            if (!exists $new->{$dir}{$path}) {
                $cb->($path); # deleted
            } elsif (!$new->{$dir}{$path}{is_dir} &&
                    ( $old->{$dir}{$path}{mtime} != $new->{$dir}{$path}{mtime} ||
                      $old->{$dir}{$path}{size}  != $new->{$dir}{$path}{size})) {
                $cb->($path); # updated
            }
        }
    }

    for my $dir (keys %$new) {
        for my $path (sort grep { !exists $old->{$dir}{$_} } keys %{$new->{$dir}}) {
            $cb->($path); # new
        }
    }
}

sub _full_scan {
    my @paths = @_;
    require File::Find;

    my %map;
    for my $path (@paths) {
        my $fp = eval { Cwd::realpath($path) } or next;
        File::Find::finddepth({
            wanted => sub {
                my $fullname = $File::Find::fullname || File::Spec->rel2abs($File::Find::name);
                $map{Cwd::realpath($File::Find::dir)}{$fullname} = _stat($fullname);
            },
            follow_fast => 1,
            follow_skip => 2,
            no_chdir => 1,
        }, $path);

        # remove root entry
        # NOTE: On MSWin32, realpath and rel2abs disagree with path separator.
        delete $map{$fp}{File::Spec->rel2abs($fp)};
    }

    return \%map;
}

sub _stat {
    my $path = shift;
    my @stat = stat $path;
    return { path => $path, mtime => $stat[9], size => $stat[7], is_dir => -d _ };
}


1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Filesys::Notify::Simple - Simple and dumb file system watcher

=head1 SYNOPSIS

  use Filesys::Notify::Simple;

  my $watcher = Filesys::Notify::Simple->new([ "." ]);
  $watcher->wait(sub {
      for my $event (@_) {
          $event->{path} # full path of the file updated
      }
  });

=head1 DESCRIPTION

Filesys::Notify::Simple is a simple but unified interface to get
notifications of changes to a given filesystem path. It utilizes
inotify2 on Linux, fsevents on OS X, kqueue on FreeBSD and
FindFirstChangeNotification on Windows if they're installed, with a
fallback to the full directory scan if they're not available.

There are some limitations in this module. If you don't like it, use
L<File::ChangeNotify>.

=over 4

=item *

There is no file name based filter. Do it in your own code.

=item *

You can not get types of events (created, updated, deleted).

=item *

Currently C<wait> method blocks.

=back

In return, this module doesn't depend on any non-core
modules. Platform specific optimizations with L<Linux::Inotify2>,
L<Mac::FSEvents>, L<Filesys::Notify::KQueue> and L<Win32::ChangeNotify>
are truely optional.

NOTE: Using L<Win32::ChangeNotify> may put additional limitations.

=over 4

=item *

L<Win32::ChangeNotify> uses FindFirstChangeNotificationA so that
Unicode characters can not be handled.
On cygwin (1.7 or later), Unicode characters should be able to be handled
when L<Win32::ChangeNotify> is not used.

=item *

If more than 64 directories are included under the specified paths,
an error occurrs.

=back

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<File::ChangeNotify> L<Mac::FSEvents> L<Linux::Inotify2> L<Filesys::Notify::KQueue>
L<Win32::ChangeNotify>

=cut
