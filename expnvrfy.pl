#!/usr/bin/perl

use strict;
use IO::Handle;
use IO::Socket;
use POSIX qw(:signal_h setsid WNOHANG);

my $CHILD_COUNT = 0;		# Child counter
my $DONE = 0;			# Set flag to true when client done
use constant TIMEOUT => 60;	# Connection time out
my (%CHILDREN, @hosts, @users, $port, $kidpid, $handle, $line);

@hosts=`cat target.list`;
@users=`cat user.list`;
$port=25;

$SIG{INT} = $SIG{TERM} = sub { $DONE++ };

for (1..$#hosts) {
  make_child($hosts[$_]);
  sleep TIMEOUT;
}

kill_children();
warn "Normal termination\n";
exit 0;

sub check_server {
  my $host=shift;
  chomp($host);

  my $sock = IO::Socket::INET->new(Proto => "tcp",
				   PeerAddr => $host,
				   PeerPort => $port)
    or die "Can't connect to port $port on $host: $!";
  
  $sock->autoflush(1);
  print STDERR "[Connected to $host:$port]\n";
  
  get_banner($sock, $host);
  foreach my $user (@users) {
    check_expn($sock, $host, $user);
    check_vrfy($sock, $host, $user);
  }
  close $sock;
}

sub get_banner {
  alarm(TIMEOUT);
  my ($sock, $host)=@_;
  my $banner = <$sock>;
  print "$host: $banner";
  alarm(0);
}

sub check_expn {
  alarm(TIMEOUT);
  my ($sock, $host, $user) = @_;
  print $sock "EXPN $user";
  my $is_exists_expn = <$sock>;
  print "$host: $is_exists_expn";
  alarm(0);
}

sub check_vrfy {
  alarm(TIMEOUT);
  my ($sock, $host, $user) = @_;
  print $sock "VRFY $user";
  my $is_exists_vrfy = <$sock>;
  print "$host: $is_exists_vrfy";
  alarm(0);
}

sub make_child {
  my $host=shift;
  my $child = launch_child(\&cleanup_child);
  if ($child) {
    $CHILD_COUNT++;
  } else {
    check_server($host);
    exit 1;
  }
}

sub cleanup_child {
  my $child = shift;
  $CHILD_COUNT--;
}

sub launch_child {
  my $callback = shift;
  my $signals = POSIX::SigSet->new(SIGINT,SIGCHLD,SIGTERM,SIGHUP);
  sigprocmask(SIG_BLOCK,$signals); # block inconvenient signals
  die("Can't fork: $!") unless defined (my $child = fork());

  if ($child) {
    $CHILDREN{$child} = $callback || 1;
    $SIG{ALRM} = $SIG{CHLD} = \&reap_child;
  } else {
    $SIG{HUP} = $SIG{INT} = $SIG{CHLD} = $SIG{TERM} = 'DEFAULT';
    $< = $>;			# set real UID to effective UID
  }
  sigprocmask(SIG_UNBLOCK,$signals); # unblock signals
  return $child;
}

sub kill_children {
  kill INT => keys %CHILDREN;
  # wait until all the children die
  # sleep while %CHILDREN;
}

sub reap_child {
  while ( (my $child = waitpid(-1,WNOHANG)) > 0) {
    delete $CHILDREN{$child};
    $DONE++;
  }
}
