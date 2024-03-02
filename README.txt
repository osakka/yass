################################################################################
#                            Yet Another Sms Server                            #
#                              by Omar Al-Sakka                                #
################################################################################

  USAGE:
   yasc           - SMS Client (for sending from machine).
   yass           - Script to start/stop the server.
   client_handler - Inet Client Communications Handler.
   queue_handler  - Queue Processor/Handler.

  NOTES:
  - When Installing, you need to modify the following variables in the
    client/queue handler: $yp="/usr/local/yass"; for the absolute installation
    path.

  - The Following Modules are used, and should be standard part of perl.
    IO::Socket, Getopt::Std, Net::hostent

  - To define the Providers, these are perl scripts in the providers directory,
    YOU WILL NEED TO ADHERE TO THE FOLLOWING RULES!
    sub _sms is required which takes a list of numbers (comma delimited), 
    followed by the message.

  - Create a User yass, and group yass.  Make Sure persmission for the spool
    directory and the log file are a+rwx, and a+rw (will be modified later on).

################################################################################
