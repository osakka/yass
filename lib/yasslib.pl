################################################################################
### yass shared library file.
### by Omar Al-Sakka
################################################################################

################################################################################
### Includes.
################################################################################
use IO::Socket;
use Getopt::Std;
use Net::hostent; 

###############################################################################
### Some Globals.
###############################################################################
$self="$0";
$send_error_code="N/A";

###############################################################################
### Print Message and Exit.
###############################################################################
sub bad_finish {
  print qq|$self: @_\n|;
  exit(0);
}

###############################################################################
### Log to file.
###############################################################################
sub logger {
  my $current_date = scalar localtime(time);

  if ( open (LOGFILE,">>$config{log_file}") ) {
    if ("@_" eq "") { print LOGFILE qq|$current_date:[$$] $!\n|; }
    else { print LOGFILE qq|$current_date:[$$] @_\n|; }
    close (LOGFILE);
  } else { finish ("cannot create log file '$config{log_file}'."); }
}

###############################################################################
### Print Message, Log, and Exit.
###############################################################################
sub finish {
  print qq|$self: @_\n|;
  logger("@_");
  exit(0);
}

###############################################################################
### System Messages.
###############################################################################
sub sys_mess {
  my ($n) = @_ or finish ("no message specified");
  my $s;
  if ($n == 0) { $s = "OK"; }
  elsif ($n == 1)  { $s="SEND FAILED, BUFFERS UNTOUCHED"; }
  elsif ($n == 2)  { $s="RETRY FAILED, BUFFERS UNTOUCHED"; }
  elsif ($n == 3)  { $s="BUFFER CONTENTS EMPTY"; }
  elsif ($n == 4)  { $s="INVALID FROM"; }
  elsif ($n == 5)  { $s="INVALID RECIPIENT(S), DIGITS ONLY, COMMA SEPERATED";}
  elsif ($n == 6)  { $s="INVALID SERVICE PROVIDER"; }
  elsif ($n == 7)  { $s="ENTER MESSAGE, '.' TO TERMINATE"; }
  elsif ($n == 8)  { $s="RECIPIENT NUMBERS REQUIRED"; }
  elsif ($n == 9)  { $s="QUEUING OFF"; }
  elsif ($n == 10) { $s="QUEUING ON"; }
  elsif ($n == 11) { $s="UNKNOWN COMMAND"; }
  else { $s = "INVALID MESSAGE REQUESTED"; }
  return "$s\n";
}

###############################################################################
### Get List of Files in a Directory.
###############################################################################
sub file_list {
  my ($dir, $rx) = @_ or finish ("file_list directory and regex required");
  if ( opendir (DIR, $dir )) {
    my @splist = grep (/$rx/, readdir (DIR));
    closedir (DIR);
    return @splist;
  } else { finish ("file_list directory missing"); }
  return 0;
}

###############################################################################
### Load Provider Def.
###############################################################################
sub load_pd {
  my ($pname) = @_ or finish ("provider def required");
  if ( $pname =~ m/(\w+)/ ) { 
    $pname = $1;
    if ( -e "$config{provider_defs}/$pname.def" ) {
      require "$config{provider_defs}/$pname.def";
      return(1);
    }
  } 
  return(0);
}

###############################################################################
### Clean Unlinker.
###############################################################################
sub cunlink {
  my (@name) = @_ or bad_finish ("required file missing.");
  foreach my $i ( 0 .. $#name ) {
    if ( $name[$i] =~ m/([\w\/\.\d]+)/ ) {
      unlink $1 or logger("cannot remove message $1 from queue");
    }
  }
  return 0;
}

###############################################################################
### Read in Config File.
### : file_name
###   config hash name.
###############################################################################
sub config_slurp {
  my ($file, $hash) = @_ or bad_finish ("required file_name missing.");
  # Check File Name.
  bad_finish ("invalid slurp filename") if ( ! $file =~ m/^([\w\.]+)$/ );
  # Slurp in File.
  if ( open (CFG, "$file") ) {
    while (<CFG>) {
      chomp ($_);       # ensure no return.
      s/\t/ /g;         # Replace tabs by space.
      s/\s/ /g;         # Replace Whitespaces with space.
      s/\s+$//g;        # Remove WhiteSpaces at endof-line.
      next if /^\s*\;/; # Ignore a Comment. (;)
      next if /^\s*$/;  # Ignore empty line.
      next if /^\s+$/;  # ignore white space.
      if (/^(\w+)\s+\"(.*)\"$/) { $$hash{lc($1)} = "$2"; next; }
      # Error if we Reach Here.
      finish ("syntax error, line $. of configuration");
    } close (CFG);
  } else { bad_finish ("opening configuration '$file' failed"); }
}

###############################################################################
### Locking Functions.
### 1 for Lock, ? for Verify, 0 to Unlock.
###############################################################################
sub lock {
  my ($file, $action) = @_ or finish ("required action missing.");

  if ($action eq "?") {
    # Get PID from Lock file if Available.
    if ( open (LOCK, "$file") ) {
      while (<LOCK>) { 
        chomp($_);  
        if ($_ =~ m/^(\d+)$/) { return $1; }
        else { finish ("invalid data in lock file"); }
      }
      close (LOCK);
    } return -1;
  }
  elsif ($action) {
    # Write The PID to the Lock File.
    if ( open (LOCK, "> $file") ) {
      print LOCK "$$\n";
      close (LOCK);
      return 1;
    } return 0;
  }
  else {
    # Delete the File if it Exists.
    if ( unlink ("$file") ) { return 1; }
    else { return 0; }
  }
}

###############################################################################
### Redirect STDIN/STDERR
###############################################################################
sub redirector {
  open(SAVE_STDOUT, ">&STDOUT");
  open(SAVE_STDERR, ">&STDERR");
  open(STDOUT, ">>$config{debug_file}") || finish ("$!");
  open(STDERR, ">&STDOUT") || finish ("$!");
  select STDOUT; $| =1;
  select STDERR; $| =1;
}

###############################################################################
### Daemon.
### Options: 0/1 (start stop)
###          lock_file
###          function (to run)
###          sleep time (between cycles).
###############################################################################
sub daemon {
  my ($action, $lock_file, $init_func, $rep_func, $sleep_timer) = @_ or 
    finish ("required action missing");

  # Start Daemon if 1.
  if ($action) {
    # Check if a Process is Running.
    my $tpid  = &lock("$lock_file", "?");
    my $ftpid = "/proc/" . $tpid;
    if ( -e "$ftpid" ) { finish (qq|daemon already running [$tpid]|); }
    else {
      print qq|$0: starting daemon [$$]\n|;
      # Daemonize.
      &redirector;
      fork && return 1;
      # Lock, otherwise Abort.
      if (&lock ("$lock_file", "1")) {
        # Call Init Function if specified.
        if ($init_func) { &$init_func; }
        # Loop while PID in Lock is Mine.
        while ( &lock("$lock_file", "?") eq "$$" ) {
          if ($rep_func) { &$rep_func; }
          else { finish ("rep_func required in daemon call"); }
          sleep($sleep_timer);
        }
      } else { finish (qq|failed to lock daemon|); }
    }
  }
  # Stop Daemon if 0.
  else {
    # Unlock and Log, or Panic.
    my $tpid  = &lock("$lock_file", "?");
    if ( &lock("$lock_file", "0") ) { 
      kill ("SIGHUP", "$tpid") or finish ("cannot kill daemon [$tpid]");
      finish (qq|daemon terminated [$tpid]|); 
    }
    else { finish (qq|daemon not running|); }
  }
  return 1;
}

###############################################################################
### Terminator.
###############################################################################
sub terminator {
  logger("terminated via signal");
  if ($server) { 
    shutdown($server, 2);
    close ($server); 
  }
  exit(1);
}

###############################################################################
### Timeout Alarm.
###############################################################################
sub t_alarm { finish("timeout alarm received"); }

###############################################################################
### Reaper.
###############################################################################
sub reaper { $waitedpid = wait; }

###############################################################################
### Signal Handler.
###############################################################################
sub signal_handler {
  my ($type) = @_ or finish ("handler requires type");
  $SIG{INT} =   \&terminator;
  $SIG{TERM} =  \&terminator;
  $SIG{QUIT} =  \&terminator;
  $SIG{PIPE} =  \&terminator;
  if ($type eq "server") { 
    $SIG{CHLD} = \&reaper;
  }
  elsif ($type eq "client") {
    $SIG{ALRM} = \&t_alarm; 
    alarm($config{connection_timeout});
  }
}

################################################################################
### Change Char to Hex.
################################################################################
sub hx {
  my($char) = @_;
  return sprintf "%%%X", ord($char);
}

################################################################################
### Q SMS.
################################################################################
sub sms_q {
  my ($hdr, $data) = @_ or finish("internal sms_q call error");
  my $fn = rand($$) . rand($$) . rand($$);
  $fn =~ s/\.//g;
  $fn = substr($fn, 0, 24);
  if ($fn =~ m/(\d+)/) { $fn = $1 }
  else { return 0; }
  if ( open (HSMSQ, "> $config{spool_dir}/$fn.h") ) { 
    print HSMSQ qq|$hdr|;
    close(HSMSQ);
    if ( open (DSMSQ, "> $config{spool_dir}/$fn.d") ) {
      print DSMSQ qq|$data\n|;
      close(DSMSQ);
      logger (qq|queued message id:$fn|);
      return 1;
    }
  }
  return 0;
}

################################################################################
### SMS Wrapper.
### Queue, Service Provider, From, Numbers, Message.
################################################################################
sub sms {
  my ($q, $sp, $fm, $ns, $mess) = @_ or finish("internal sms call error");
  chomp($mess);
  if ($q) { 
    my $tsq = "To \"$ns\"\nFrom \"$fm\"\nService \"$sp\"\nStatus \"0\"\n";
    return (sms_q ("$tsq", "$mess")); 
  }
  else {
    # Check Provider.
    if (load_pd("$sp}")) {
      # Check for SMS Function.
      if (defined(&_sms)) {
        # SMS The Message.
        if ( &_sms("$ns", "$mess") ) {
          logger (qq|direct:$sp:$fm:$ns:$mess|);
          return 1;
        } 
        # Failed to Deliver SMS Message.
        else { return 0; }
      } 
      # No SMS Function.
      else { 
        logger ("undefined sms for provider"); 
        return 0;
      }
    }
    # Invalid Provider.
    else {
      logger ("invalid provider for requested");
      return 0;
    }
  }
}

################################################################################
### Alert Administrator.
################################################################################
sub admin_alert {
  my ($subj, $mess) = @_ or finish ("alert subject and message required");

  if (open (MAIL, "|$config{sendmail_bin}")) {
    print MAIL "From: $config{server_user}\n"
             . "To: $config{admin_email}\n"
             . "Subject: $subj\n"
             . "Content-type: text\n\n$mess\n";
    close(MAIL);
  } else { &finish("Can't open $sendmail!"); }
}

################################################################################
### Main Initialization.
################################################################################
sub init {
  my ($cf) = @_ or bad_finish ("config filename required");
  delete @ENV{'IFS', 'CDPATH', 'PATH', 'ENV', 'BASH_ENV'};
  $|++;
  &config_slurp($cf, \%config);
}

1;
