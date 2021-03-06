# Copyright (C) 2013 Ishraq Ibne Ashraf <ishraq@tinkerforge.com>
# Copyright (C) 2014 Matthias Bolte <matthias@tinkerforge.com>
#
# Redistribution and use in source and binary forms of this file,
# with or without modification, are permitted. See the Creative
# Commons Zero (CC0 1.0) License for more details.

=pod

=encoding utf8

=head1 NAME

Tinkerforge::IPConnection - TCP/IP connection handling

=cut

# package definition
package Tinkerforge::IPConnection;

# using modules
use strict;
use warnings;
use Carp;
use threads;
use threads::shared;
use Thread::Queue;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use IO::Socket::INET;
use Tinkerforge::Device;
use Tinkerforge::Error;

=head1 CONSTANTS

=over

=item CALLBACK_ENUMERATE

This constant is used with the register_callback() subroutine to specify
the CALLBACK_ENUMERATE callback.

=cut

use constant CALLBACK_ENUMERATE => 253;

=item CALLBACK_CONNECTED

This constant is used with the register_callback() subroutine to specify
the CALLBACK_CONNECTED callback.

=cut

use constant CALLBACK_CONNECTED => 0;

=item CALLBACK_DISCONNECTED

This constant is used with the register_callback() subroutine to specify
the CALLBACK_DISCONNECTED callback.

=cut

use constant CALLBACK_DISCONNECTED => 1;

=item ENUMERATION_TYPE_AVAILABLE

Possible value for $enumeration_type parameter of CALLBACK_ENUMERATE callback.

=cut

use constant ENUMERATION_TYPE_AVAILABLE => 0;

=item ENUMERATION_TYPE_CONNECTED

Possible value for $enumeration_type parameter of CALLBACK_ENUMERATE callback.

=cut

use constant ENUMERATION_TYPE_CONNECTED => 1;

=item ENUMERATION_TYPE_DISCONNECTED

Possible value for $enumeration_type parameter of CALLBACK_ENUMERATE callback.

=cut

use constant ENUMERATION_TYPE_DISCONNECTED => 2;

=item CONNECT_REASON_REQUEST

Possible value for $connect_reason parameter of CALLBACK_CONNECTED callback.

=cut

use constant CONNECT_REASON_REQUEST => 0;

=item CONNECT_REASON_AUTO_RECONNECT

Possible value for $connect_reason parameter of CALLBACK_CONNECTED callback.

=cut

use constant CONNECT_REASON_AUTO_RECONNECT => 1;

=item DISCONNECT_REASON_REQUEST

Possible value for $disconnect_reason parameter of CALLBACK_DISCONNECTED callback.

=cut

use constant DISCONNECT_REASON_REQUEST => 0;

=item DISCONNECT_REASON_ERROR

Possible value for $disconnect_reason parameter of CALLBACK_DISCONNECTED callback.

=cut

use constant DISCONNECT_REASON_ERROR => 1;

=item DISCONNECT_REASON_SHUTDOWN

Possible value for $disconnect_reason parameter of CALLBACK_DISCONNECTED callback.

=cut

use constant DISCONNECT_REASON_SHUTDOWN => 2;

=item CONNECTION_STATE_DISCONNECTED

Possible return value of the get_connection_state() subroutine.

=cut

use constant CONNECTION_STATE_DISCONNECTED => 0;

=item CONNECTION_STATE_CONNECTED

Possible return value of the get_connection_state() subroutine.

=cut

use constant CONNECTION_STATE_CONNECTED => 1;

=item CONNECTION_STATE_PENDING

Possible return value of the get_connection_state() subroutine.

=cut

use constant CONNECTION_STATE_PENDING => 2;

=back
=cut

use constant _FUNCTION_ENUMERATE => 254;
use constant _FUNCTION_DISCONNECT_PROBE => 128;

use constant _BROADCAST_UID => 0;

use constant _QUEUE_EXIT => 0;
use constant _QUEUE_META => 1;
use constant _QUEUE_PACKET => 2;

use constant _DISCONNECT_PROBE_INTERVAL => 5;

# the socket variable
my $IPCONNECTION_SOCKET = undef;

# lock(s)
our $CONNECT_LOCK :shared;
our $SEND_LOCK :shared;
our $SEQUENCE_NUMBER_LOCK :shared;


=head1 FUNCTIONS

=over

=item new()

Creates an IP Connection object that can be used to enumerate the available
devices. It is also required for the constructor of Bricks and Bricklets.

=cut

# the constructor
sub new
{
	my ($class) = @_;

	my $self :shared = shared_clone({host => undef,
									 port => undef,
									 timeout => 2.5,
									 sequence_number => 0,
									 auto_reconnect => 1,
									 auto_reconnect_allowed => 0,
									 auto_reconnect_pending => 0,
									 devices => shared_clone({}),
									 registered_callbacks => shared_clone({}),
									 socket_id => 0,
									 receive_flag => 0,
									 receive_thread => undef,
									 disconnect_probe_thread => undef,
									 disconnect_probe_queue => Thread::Queue->new(),
									 callback_thread => undef,
									 callback_queue => Thread::Queue->new()
									});

	bless($self, $class);

	return $self;
}

=item connect()

Creates a TCP/IP connection to the given $host and $port. The host and port
can refer to a Brick Daemon or to a WIFI/Ethernet Extension.

Devices can only be controlled when the connection was established
successfully.

Blocks until the connection is established and throws an exception if there
is no Brick Daemon or WIFI/Ethernet Extension listening at the given
host and port.

=cut

sub connect
{
	my ($self, $host, $port) = @_;

	if(defined($IPCONNECTION_SOCKET) && $self->{auto_reconnect_pending} == 0)
	{
		croak(Tinkerforge::Error->_new(Tinkerforge::Error->ALREADY_CONNECTED, "Already connected to $self->{host}:$self->{host}"));
        return 1;
	}
	elsif(!defined($IPCONNECTION_SOCKET) && $self->{auto_reconnect_pending} == 0)
	{
		$self->{host} = $host;
		$self->{port} = $port;
		$self->_handle_connect(&CONNECT_REASON_REQUEST);
        return 1;
	}
    else
    {
        croak('Undefined connect state');
    }

	return 1;
}

sub _handle_connect
{
	lock($Tinkerforge::IPConnection::CONNECT_LOCK);

	my ($self, $connect_reason) = @_;

	#normal connect request
	if($connect_reason == &CONNECT_REASON_REQUEST && $self->{auto_reconnect_pending} == 0 && !defined($IPCONNECTION_SOCKET))
	{
		$IPCONNECTION_SOCKET = undef;

		eval
		{
			$IPCONNECTION_SOCKET = IO::Socket::INET->new(PeerAddr => $self->{host},
														 PeerPort => $self->{port},
														 Proto => 'tcp',
														 Type => SOCK_STREAM,
														 Blocking => 1);

			$IPCONNECTION_SOCKET->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1);

			$| = 1;
			$IPCONNECTION_SOCKET->send('');
		};
		if($!)
		{
			if(defined($IPCONNECTION_SOCKET))
			{
				$IPCONNECTION_SOCKET->shutdown(2);
				$IPCONNECTION_SOCKET->close();
			}

			$IPCONNECTION_SOCKET = undef;

			croak(Tinkerforge::Error->_new(Tinkerforge::Error->CONNECT_FAILED, "Can't connect to	$self->{host}:$self->{port}"));
		}
		else
		{
			if(!defined($self->{callback_thread}))
			{
				$self->{socket_id} ++;
				$self->{callback_thread} = shared_clone(threads->create(\&_callback_thread_subroutine, $self));

				if(defined($self->{callback_thread}))
				{
					if(!defined($self->{receive_thread}))
					{
						$self->{receive_thread} = shared_clone(threads->create(\&_receive_thread_subroutine, $self));

						if(defined($self->{receive_thread}))
						{
							if(!defined($self->{disconnect_probe_thread}))
							{
								$self->{disconnect_probe_thread} = shared_clone(threads->create(\&_disconnect_probe_thread_subroutine, $self));

								if(defined($self->{disconnect_probe_thread}))
								{
									if(defined($self->{callback_thread}))
									{
										$self->{auto_reconnect_allowed} = 0;
										$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_CONNECTED, &CONNECT_REASON_REQUEST, $self->{socket_id}]);
									}
									else
									{
										$self->{auto_reconnect_pending} = 0;

										if(defined($self->{disconnect_probe_thread}))
										{
											$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
											$self->{disconnect_probe_thread}->join();
											$self->{disconnect_probe_thread} = undef;
										}

										if(defined($self->{receive_thread}))
										{
											$self->{receive_flag} = undef;

											if(defined($IPCONNECTION_SOCKET))
											{
												$IPCONNECTION_SOCKET->shutdown(2);
												$IPCONNECTION_SOCKET->close();
											}
											$IPCONNECTION_SOCKET = undef;

											$self->{receive_thread}->join();
											$self->{receive_thread} = undef;
										}

										if(defined($self->{callback_thread}))
										{
											$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
											$self->{callback_thread}->join();
											$self->{callback_thread} = undef;
										}

										croak('Thread create error');
									}
								}
								else
								{
									$self->{auto_reconnect_pending} = 0;
									$self->{auto_reconnect_allowed} = 0;

									if(defined($self->{disconnect_probe_thread}))
									{
										$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
										$self->{disconnect_probe_thread}->join();
										$self->{disconnect_probe_thread} = undef;
									}

									if(defined($self->{receive_thread}))
									{
										$self->{receive_flag} = undef;

										if(defined($IPCONNECTION_SOCKET))
										{
											$IPCONNECTION_SOCKET->shutdown(2);
											$IPCONNECTION_SOCKET->close();
										}
										$IPCONNECTION_SOCKET = undef;

										$self->{receive_thread}->join();
										$self->{receive_thread} = undef;
									}

									if(defined($self->{callback_thread}))
									{
										$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
										$self->{callback_thread}->join();
										$self->{callback_thread} = undef;
									}

									croak('Thread create error');
								}
							}
							else
							{
								$self->{auto_reconnect_pending} = 0;
								$self->{auto_reconnect_allowed} = 0;

								if(defined($self->{disconnect_probe_thread}))
								{
									$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
									$self->{disconnect_probe_thread}->join();
									$self->{disconnect_probe_thread} = undef;
								}

								if(defined($self->{receive_thread}))
								{
									$self->{receive_flag} = undef;

									if(defined($IPCONNECTION_SOCKET))
									{
										$IPCONNECTION_SOCKET->shutdown(2);
										$IPCONNECTION_SOCKET->close();
									}
									$IPCONNECTION_SOCKET = undef;

									$self->{receive_thread}->join();
									$self->{receive_thread} = undef;
								}

								if(defined($self->{callback_thread}))
								{
									$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
									$self->{callback_thread}->join();
									$self->{callback_thread} = undef;
								}

								croak('Thread create error');
							}
						}
						else
						{
							$self->{auto_reconnect_pending} = 0;
							$self->{auto_reconnect_allowed} = 0;

							if(defined($self->{disconnect_probe_thread}))
							{
								$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
								$self->{disconnect_probe_thread}->join();
								$self->{disconnect_probe_thread} = undef;
							}

							if(defined($self->{receive_thread}))
							{
								$self->{receive_flag} = undef;

								if(defined($IPCONNECTION_SOCKET))
								{
									$IPCONNECTION_SOCKET->shutdown(2);
									$IPCONNECTION_SOCKET->close();
								}
								$IPCONNECTION_SOCKET = undef;

								$self->{receive_thread}->join();
								$self->{receive_thread} = undef;
							}

							if(defined($self->{callback_thread}))
							{
								$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
								$self->{callback_thread}->join();
								$self->{callback_thread} = undef;
							}

							croak('Thread create error');
						}
					}
					else
					{
						$self->{auto_reconnect_pending} = 0;
						$self->{auto_reconnect_allowed} = 0;

						if(defined($self->{disconnect_probe_thread}))
						{
							$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
							$self->{disconnect_probe_thread}->join();
							$self->{disconnect_probe_thread} = undef;
						}

						if(defined($self->{receive_thread}))
						{
							$self->{receive_flag} = undef;

							if(defined($IPCONNECTION_SOCKET))
							{
								$IPCONNECTION_SOCKET->shutdown(2);
								$IPCONNECTION_SOCKET->close();
							}
							$IPCONNECTION_SOCKET = undef;

							$self->{receive_thread}->join();
							$self->{receive_thread} = undef;
						}

						if(defined($self->{callback_thread}))
						{
							$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
							$self->{callback_thread}->join();
							$self->{callback_thread} = undef;
						}

						croak('Thread create error');
					}
				}
				else
				{
					$self->{auto_reconnect_pending} = 0;
					$self->{auto_reconnect_allowed} = 0;

					if(defined($self->{disconnect_probe_thread}))
					{
						$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
						$self->{disconnect_probe_thread}->join();
						$self->{disconnect_probe_thread} = undef;
					}

					if(defined($self->{receive_thread}))
					{
						$self->{receive_flag} = undef;

						if(defined($IPCONNECTION_SOCKET))
						{
							$IPCONNECTION_SOCKET->shutdown(2);
							$IPCONNECTION_SOCKET->close();
						}
						$IPCONNECTION_SOCKET = undef;

						$self->{receive_thread}->join();
						$self->{receive_thread} = undef;
					}

					if(defined($self->{callback_thread}))
					{
						$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
						$self->{callback_thread}->join();
						$self->{callback_thread} = undef;
					}

					croak('Thread create error');
				}
			}
			else
			{
				$self->{auto_reconnect_pending} = 0;
				$self->{auto_reconnect_allowed} = 0;

				if(defined($self->{disconnect_probe_thread}))
				{
					$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
					$self->{disconnect_probe_thread}->join();
					$self->{disconnect_probe_thread} = undef;
				}

				if(defined($self->{receive_thread}))
				{
					$self->{receive_flag} = undef;

					if(defined($IPCONNECTION_SOCKET))
					{
						$IPCONNECTION_SOCKET->shutdown(2);
						$IPCONNECTION_SOCKET->close();
					}
					$IPCONNECTION_SOCKET = undef;

					$self->{receive_thread}->join();
					$self->{receive_thread} = undef;
				}

				if(defined($self->{callback_thread}))
				{
					$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
					$self->{callback_thread}->join();
					$self->{callback_thread} = undef;
				}

				croak('Thread create error');
			}
		}
	}

	#auto reconnect handle
	elsif($connect_reason == &CONNECT_REASON_AUTO_RECONNECT &&
		  $self->{auto_reconnect} == 1 &&
		  $self->{auto_reconnect_allowed} == 1 &&
		  $self->{auto_reconnect_pending} == 1)
	{
		#while loop of the auto reconnect
		while(1)
		{
			#disconnect can stop auto reconnect process if any
			if($self->{auto_reconnect_allowed} == 1)
			{
				$IPCONNECTION_SOCKET = undef;

				eval
				{
					$IPCONNECTION_SOCKET = IO::Socket::INET->new(PeerAddr => $self->{host},
																 PeerPort => $self->{port},
																 Proto => 'tcp',
																 Type => SOCK_STREAM,
																 Blocking => 1);

					$IPCONNECTION_SOCKET->setsockopt(IPPROTO_TCP, TCP_NODELAY, 1);
					$| = 1;
					$IPCONNECTION_SOCKET->send('');

				};

				if($!)
				{
					if(defined($IPCONNECTION_SOCKET))
					{
						$IPCONNECTION_SOCKET->shutdown(2);
						$IPCONNECTION_SOCKET->close();

					}

					$IPCONNECTION_SOCKET = undef;

					next;
				}
				else
				{
					if(!defined($self->{receive_thread}))
					{
						$self->{socket_id} ++;

						$self->{receive_thread} = shared_clone(threads->create(\&_receive_thread_subroutine, $self));

						if(defined($self->{receive_thread}))
						{
							if(!defined($self->{disconnect_probe_thread}))
							{
								$self->{disconnect_probe_thread} = shared_clone(threads->create(\&_disconnect_probe_thread_subroutine, $self));

								if(defined($self->{disconnect_probe_thread}))
								{
									$self->{auto_reconnect_pending} = 0;
									$self->{auto_reconnect_allowed} = 0;
									$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_CONNECTED, &CONNECT_REASON_AUTO_RECONNECT, $self->{socket_id}]);

									#exit auto reconnect loop
									last;
								}
								else
								{
									$self->{auto_reconnect_allowed} = 0;
									$self->{auto_reconnect_pending} = 0;

									if(defined($self->{disconnect_probe_thread}))
									{
										$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
										$self->{disconnect_probe_thread}->join();
										$self->{disconnect_probe_thread} = undef;
									}

									if(defined($self->{receive_thread}))
									{
										$self->{receive_flag} = undef;

										if(defined($IPCONNECTION_SOCKET))
										{
											$IPCONNECTION_SOCKET->shutdown(2);
											$IPCONNECTION_SOCKET->close();
										}
										$IPCONNECTION_SOCKET = undef;

										$self->{receive_thread}->join();
										$self->{receive_thread} = undef;
									}

									if(defined($self->{callback_thread}))
									{
										$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
										$self->{callback_thread}->join();
										$self->{callback_thread} = undef;
									}

									croak('Thread create error');
								}
							}
							else
							{
								$self->{auto_reconnect_allowed} = 0;
								$self->{auto_reconnect_pending} = 0;

								if(defined($self->{disconnect_probe_thread}))
								{
									$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
									$self->{disconnect_probe_thread}->join();
									$self->{disconnect_probe_thread} = undef;
								}

								if(defined($self->{receive_thread}))
								{
									$self->{receive_flag} = undef;

									if(defined($IPCONNECTION_SOCKET))
									{
										$IPCONNECTION_SOCKET->shutdown(2);
										$IPCONNECTION_SOCKET->close();
									}
									$IPCONNECTION_SOCKET = undef;

									$self->{receive_thread}->join();
									$self->{receive_thread} = undef;
								}

								if(defined($self->{callback_thread}))
								{
									$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
									$self->{callback_thread}->join();
									$self->{callback_thread} = undef;
								}

								croak('Thread create error');
							}
						}
						else
						{
							$self->{auto_reconnect_allowed} = 0;
							$self->{auto_reconnect_pending} = 0;

							if(defined($self->{disconnect_probe_thread}))
							{
								$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
								$self->{disconnect_probe_thread}->join();
								$self->{disconnect_probe_thread} = undef;
							}

							if(defined($self->{receive_thread}))
							{
								$self->{receive_flag} = undef;

								if(defined($IPCONNECTION_SOCKET))
								{
									$IPCONNECTION_SOCKET->shutdown(2);
									$IPCONNECTION_SOCKET->close();
								}
								$IPCONNECTION_SOCKET = undef;

								$self->{receive_thread}->join();
								$self->{receive_thread} = undef;
							}

							if(defined($self->{callback_thread}))
							{
								$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
								$self->{callback_thread}->join();
								$self->{callback_thread} = undef;
							}

							croak('Thread create error');
						}
					}
					else
					{
						$self->{auto_reconnect_allowed} = 0;
						$self->{auto_reconnect_pending} = 0;

						if(defined($self->{disconnect_probe_thread}))
						{
							$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
							$self->{disconnect_probe_thread}->join();
							$self->{disconnect_probe_thread} = undef;
						}

						if(defined($self->{receive_thread}))
						{
							$self->{receive_flag} = undef;

							if(defined($IPCONNECTION_SOCKET))
							{
								$IPCONNECTION_SOCKET->shutdown(2);
								$IPCONNECTION_SOCKET->close();
							}
							$IPCONNECTION_SOCKET = undef;

							$self->{receive_thread}->join();
							$self->{receive_thread} = undef;
						}

						if(defined($self->{callback_thread}))
						{
							$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
							$self->{callback_thread}->join();
							$self->{callback_thread} = undef;
						}

						croak('Thread create error');
					}
				}
			}
			else
			{
				#exit auto reconnect
				$self->{auto_reconnect_pending} = 0;
				last;
			}
		}
	}
	else
	{
		croak('Undefined connect state');
	}

	return 1;
}

=item disconnect()

Disconnects the TCP/IP connection from the Brick Daemon or the WIFI/Ethernet
Extension.

=cut

sub disconnect
{
	my ($self) = @_;

	$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_DISCONNECTED, &DISCONNECT_REASON_REQUEST, $self->{socket_id}]);

	if(defined($self->{disconnect_probe_thread}))
	{
		$self->{disconnect_probe_thread}->join();
		$self->{disconnect_probe_thread} = undef;
	}

	if(defined($self->{receive_thread}))
	{
		$self->{receive_thread}->join();
		$self->{receive_thread} = undef;
	}

	if(defined($self->{callback_thread}))
	{
		$self->{callback_thread}->join();
		$self->{callback_thread} = undef
	}

	return 1;
}

=item get_connection_state()

Can return the following states:

* IPConnection->CONNECTION_STATE_DISCONNECTED (0): No connection is established.
* IPConnection->CONNECTION_STATE_CONNETED (1): A connection to the Brick Daemon
  or the WIFI/Ethernet Extension  is established.
* IPConnection->CONNECTION_STATE_PENDING (2): IP Connection is currently trying
  to connect.

=cut

sub get_connection_state
{
	my ($self) = @_;

	if(defined($IPCONNECTION_SOCKET) && $self->{auto_reconnect_pending} == 0)
	{
		return &CONNECTION_STATE_CONNECTED;
	}

	if(!defined($IPCONNECTION_SOCKET) && $self->{auto_reconnect_pending} == 1)
	{
		return  &CONNECTION_STATE_PENDING;
	}

	if(!defined($IPCONNECTION_SOCKET) && $self->{auto_reconnect_pending} == 0)
	{
		return &CONNECTION_STATE_DISCONNECTED;
	}

	return 1; # FIXME
}

=item set_auto_reconnect()

Enables or disables auto-reconnect. If auto-reconnect is enabled,
the IP Connection will try to reconnect to the previously given
host and port, if the connection is lost.

Default value is 1.

=cut

sub set_auto_reconnect
{
	my ($self, $auto_reconnect) = @_;

	$self->{auto_reconnect} = $auto_reconnect;
}

=item get_auto_reconnect()

Returns 1 if auto-reconnect is enabled, 0 otherwise.

=cut

sub get_auto_reconnect
{
	my ($self) = @_;

	return $self->{auto_reconnect};
}

=item set_timeout()

Sets the timeout in seconds for getters and for setters for which the
response expected flag is activated.

Default timeout is 2.5.

=cut

sub set_timeout
{
	my ($self, $timeout) = @_;

	if($timeout < 0)
	{
		croak('Timeout cannot be negative');
	}
	else
	{
		$self->{auto_reconnect} = $timeout;
	}
}

=item get_timeout()

Returns the timeout as set by set_timeout().

=cut

sub get_timeout
{
	my ($self) = @_;

	return $self->{timeout};
}

=item enumerate()

Broadcasts an enumerate request. All devices will respond with an enumerate
callback.

=cut

sub enumerate
{
	my ($self) = @_;

	$self->_ipconnection_send($self->_create_packet_header(undef, 8, &_FUNCTION_ENUMERATE));
}

=item register_callback()

Registers a callback with ID $id to the function named $callback.

=back
=cut

sub register_callback
{
	my ($self, $function_id, $function_name) = @_;

	$self->{registered_callbacks}->{$function_id} = '\&'.caller.'::'.$function_name;
}

sub _create_packet_header
{
	my ($self, $device, $length, $function_id) = @_;

	my $uid = &_BROADCAST_UID;
	my $seq_res_oth = $self->_get_next_sequence_number() << 4;
	my $err_fut = undef;

	if(defined($device))
	{
		$uid = $device->{super}->{uid};

		if($device->get_response_expected($function_id))
		{
			#setting response expected bit
			$seq_res_oth |= (1<<3);
		}
		else
		{
			#clearing response expected bit
			$seq_res_oth &= ~(1<<3);
		}

		#clearing other_options bits
		$seq_res_oth &= ~(1<<0);
		$seq_res_oth &= ~(1<<1);
		$seq_res_oth &= ~(1<<2);

		$err_fut = 0;
		#clearing error_code bits
		$err_fut &= ~(1<<6);
		$err_fut &= ~(1<<7);

		#clearing future_use bits
		$err_fut &= ~(1<<0);
		$err_fut &= ~(1<<1);
		$err_fut &= ~(1<<2);
		$err_fut &= ~(1<<3);
		$err_fut &= ~(1<<4);
		$err_fut &= ~(1<<5);

		return pack('(V C C C C)<', $uid, $length, $function_id, $seq_res_oth, $err_fut);
	}
	else
	{
		#clearing response expected bit
		$seq_res_oth &= ~(1<<3);

		#clearing other_options bits
		$seq_res_oth &= ~(1<<0);
		$seq_res_oth &= ~(1<<1);
		$seq_res_oth &= ~(1<<2);

		$err_fut = 0;
		#clearing error_code bits
		$err_fut &= ~(1<<6);
		$err_fut &= ~(1<<7);

		#clearing future_use bits
		$err_fut &= ~(1<<0);
		$err_fut &= ~(1<<1);
		$err_fut &= ~(1<<2);
		$err_fut &= ~(1<<3);
		$err_fut &= ~(1<<4);
		$err_fut &= ~(1<<5);

		return pack('(V C C C C)<', $uid, $length, $function_id, $seq_res_oth, $err_fut);
	}

	return 1;
}

sub _get_next_sequence_number
{
	lock($Tinkerforge::IPConnection::SEQUENCE_NUMBER_LOCK);

	my ($self) = @_;

	if($self->{sequence_number} >= 0 && $self->{sequence_number} < 15)
	{
		$self->{sequence_number} ++;
		return $self->{sequence_number};
	}
	else
	{
		$self->{sequence_number} = 0;
		$self->{sequence_number} ++;
		return $self->{sequence_number};
	}

	return 1;
}

sub _ipconnection_send
{
	lock($Tinkerforge::IPConnection::SEND_LOCK);

	my ($self, $packet) = @_;

	if(defined($IPCONNECTION_SOCKET) && $self->{auto_reconnect_pending} == 0)
	{
		eval
		{
			$| = 1;
			$IPCONNECTION_SOCKET->send($packet);
		};

		if($!)
		{
			$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_DISCONNECTED, &DISCONNECT_REASON_ERROR, $self->{socket_id}]);

			croak(Tinkerforge::Error->_new(Tinkerforge::Error->NOT_CONNECTED, 'Not connected'));
		}
	}
	else
	{
		croak(Tinkerforge::Error->_new(Tinkerforge::Error->NOT_CONNECTED, 'Not connected'));
	}

	return 1;
}

sub _get_uid_from_data
{
	my ($self, $data) = @_;

	my @data_arr = undef;

	@data_arr = split('', $data);

	if(scalar(@data_arr) >= 8)
	{
		return unpack('(V)<', $data_arr[0].$data_arr[1].$data_arr[2].$data_arr[3]);
	}

	return 1;
}

sub _get_len_from_data
{
	my ($self, $data) = @_;

	my @data_arr = undef;

	@data_arr = split('', $data);

	if(scalar(@data_arr) >= 8)
	{
		return unpack('(C)<', $data_arr[4]);
	}

	return 1;
}

sub _get_fid_from_data
{
	my ($self, $data) = @_;

	my @data_arr = undef;

	@data_arr = split('', $data);

	if(scalar(@data_arr) >= 8)
	{
		return unpack('(C)<', $data_arr[5]);
	}

	return 1;
}

sub _get_seq_from_data
{
	my ($self, $data) = @_;

	my @data_arr = undef;
	my @bit_arr = undef;
	my $seq = undef;

	@data_arr = split('', $data);

	if(scalar(@data_arr) >= 8)
	{
		@bit_arr = split('', unpack('(b8)<', $data_arr[6]));
		$seq = $bit_arr[7].$bit_arr[6].$bit_arr[5].$bit_arr[4];
		return oct("0b$seq");
	}

	return 1;
}

sub _get_err_from_data
{
	my ($self, $data) = @_;

	my @data_arr = undef;
	my @bit_arr = undef;
	my $err = undef;

	@data_arr = split('', $data);

	if(scalar(@data_arr) >= 8)
	{
		@bit_arr = split('', unpack('(b8)<', $data_arr[7]));
		$err = $bit_arr[7].$bit_arr[6];
		return oct("0b$err");
	}

	return 1;
}

sub _get_payload_from_data
{
	my ($self, $data) = @_;

	my @data_arr = undef;
	my $payload = undef;

	@data_arr = split('', $data);

	if(scalar(@data_arr) > 8)
	{
		for(my $i = 8; $i < scalar(@data_arr); $i++)
		{
			$payload .= $data_arr[$i];
		}
		return $payload;
	}

	return 1;
}

sub _handle_packet
{
	my ($self, $packet) = @_;

	my $fid = $self->_get_fid_from_data($packet);
	my $seq = $self->_get_seq_from_data($packet);

	if($seq == 0 && $fid == &CALLBACK_ENUMERATE)
	{
		if(defined($self->{registered_callbacks}->{&CALLBACK_ENUMERATE}))
		{
			$self->{callback_queue}->enqueue([&_QUEUE_PACKET, $packet, undef, undef]);
		}
		return 1;
	}

	my $uid = $self->_get_uid_from_data($packet);

	if(!defined($self->{devices}->{$uid}))
	{
		#response from unknown device, ignoring
		return 1;
	}

	if($seq == 0)
	{
		if(defined($self->{devices}->{$uid}))
		{
            my $_device = $self->{devices}->{$uid}; 
            my $_err_code = $_device->{super}->{ipcon}->_get_err_from_data($packet);
            
            if($_err_code != 0)
            {
                if($_err_code == 1)
                {
                    croak(Tinkerforge::Error->_new(Tinkerforge::Error->INVALID_PARAMETER, "Got invalid parameter for function $fid"));
                    return 1;
                }
                elsif($_err_code == 2)
                {
                    croak(Tinkerforge::Error->_new(Tinkerforge::Error->FUNCTION_NOT_SUPPORTED, "Function $fid is not supported"));
                    return 1;
                }    
                else
                {
                    croak(Tinkerforge::Error->_new(Tinkerforge::Error->UNKNOWN_ERROR, "Function $fid returned an unknown error"));
                    return 1;
                }     
            }
			$self->{callback_queue}->enqueue([&_QUEUE_PACKET, $packet, undef, undef]);
		}
		return 1;
	}

	my $_fid = $self->{devices}->{$uid}->{super}->{expected_response_function_id};
	my $_seq = $self->{devices}->{$uid}->{super}->{expected_response_sequence_number};

	if($$_fid == $fid && $$_seq == $seq)
	{
		$self->{devices}->{$uid}->{super}->{response_queue}->enqueue($packet);
		return 1;
	}

	return 1;
}

# thread subroutines

sub _receive_thread_subroutine
{
	my ($self) = @_;

	my $data = '';
	my @data_arr = ();
	my $data_pending_flag = undef;

	$self->{receive_flag} = 1;
	my $socket_id = $self->{socket_id};

	while(defined($self->{receive_flag}))
	{
		if(defined($IPCONNECTION_SOCKET))
		{
			$data = '';

			#blocking call

			eval
			{
				$IPCONNECTION_SOCKET->recv($data, 8192);
			};

			if($! && defined($self->{receive_flag}))
			{
				$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_DISCONNECTED, &DISCONNECT_REASON_SHUTDOWN, $socket_id]);
				last;
			}

			if($! && !defined($self->{receive_flag}))
			{
				$self->{auto_reconnect_allowed} = 1;
				last;
			}

			if(length($data) == 0 && defined($self->{receive_flag}))
			{
				$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_DISCONNECTED, &DISCONNECT_REASON_ERROR, $socket_id]);
				last;
			}

			if(length($data) == 0 && !defined($self->{receive_flag}))
			{
				last;
			}

			if($data_pending_flag)
			{
				@data_arr = (@data_arr, split('', $data));
				goto MORE_BYTES_TO_PROCCESS;
			}
			else
			{
				@data_arr = split('', $data);

				MORE_BYTES_TO_PROCCESS:

				if(scalar(@data_arr) >= 8)
				{
					my $i = undef;

					for($i = 8; $i <= unpack('C', $data_arr[4])-1; $i++)
					{
						if(defined($data_arr[$i]))
						{
							next;
						}
						else
						{
							last;
						}
					}

					if($i == unpack('C', $data_arr[4]))
					{
						my $packet_to_handle = join('', @data_arr[0 .. (unpack('C', $data_arr[4]))-1]);
						my $len = unpack('C', $data_arr[4]);

						$self->_handle_packet($packet_to_handle);

						while($len > 0)
						{
							shift (@data_arr);
							$len --;
						}

						if(scalar(@data_arr) == 0)
						{
							$data_pending_flag = undef;
							next;
						}
						elsif(scalar(@data_arr) >= 8)
						{
							goto MORE_BYTES_TO_PROCCESS;
						}
						elsif(scalar(@data_arr) != 0 && scalar(@data_arr) < 8 )
						{
							$data_pending_flag = 1;
							next;
						}
						else
						{
							next;
						}
					}
					elsif($i < unpack('C', $data_arr[4]))
					{
						$data_pending_flag = 1;
						goto next;
					}
					else
					{
						next;
					}
				}
				elsif(scalar(@data_arr) != 0)
				{
					#the header is incomplete
					$data_pending_flag = 1;
					next;
				}
				else
				{
					next;
				}
			}
		}
	}

	return 1;
}

sub _callback_thread_subroutine
{
	my ($self) = @_;

	while(1)
	{
		my $_callback_queue_data_arr_ref = $self->{callback_queue}->dequeue();
		my ($kind, $data_or_callback, $reason, $socket_id) = @{$_callback_queue_data_arr_ref};

		if($kind == &_QUEUE_EXIT)
		{
			#exit callback thread
			last;
		}

		if($kind == &_QUEUE_META)
		{
			#exit callback thread
			$self->_dispatch_meta($data_or_callback, $reason, $socket_id);
		}

		if($kind == &_QUEUE_PACKET)
		{
			#exit callback thread
			$self->_dispatch_packet($data_or_callback);
		}
	}

	return 1;
}

sub _dispatch_meta
{
	my ($self, $callback, $reason, $socket_id) = @_;

	if(defined($callback))
	{
		if(defined($reason))
		{
			if($callback == &CALLBACK_CONNECTED)
			{
				if($reason == &CONNECT_REASON_REQUEST)
				{
					if(defined($self->{registered_callbacks}->{&CALLBACK_CONNECTED}))
					{
						#call the callback with connect reason as request
						eval("$self->{registered_callbacks}->{&CALLBACK_CONNECTED}(&CONNECT_REASON_REQUEST)");
						return 1;
					}
				}

				if($reason == &CONNECT_REASON_AUTO_RECONNECT)
				{
					if(defined($self->{registered_callbacks}->{&CALLBACK_CONNECTED}))
					{
						#call the callback with connect reason as request
						eval("$self->{registered_callbacks}->{&CALLBACK_CONNECTED}(&CONNECT_REASON_AUTO_RECONNECT)");
						return 1;
					}
				}
			}

			if($callback == &CALLBACK_DISCONNECTED)
			{
				if($reason == &DISCONNECT_REASON_REQUEST)
				{
					$self->{auto_reconnect_pending} = 0;
					$self->{auto_reconnect_allowed} = 0;

					if(defined($self->{disconnect_probe_thread}))
					{
						$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);
					}

					if(defined($self->{receive_thread}))
					{
						$self->{receive_flag} = undef;
					}

					if(defined($IPCONNECTION_SOCKET))
					{
						$IPCONNECTION_SOCKET->shutdown(2);
						$IPCONNECTION_SOCKET->close();
					}

					$IPCONNECTION_SOCKET = undef;

					if(defined($self->{callback_thread}))
					{
						$self->{callback_queue}->enqueue([&_QUEUE_EXIT, undef, undef, undef]);
					}

					if(defined($self->{registered_callbacks}->{&CALLBACK_DISCONNECTED}))
					{
						#call the callback with disconnect reason as request
						eval("$self->{registered_callbacks}->{&CALLBACK_DISCONNECTED}(&DISCONNECT_REASON_REQUEST)");
					}

					return 1;
				}

				if($reason == &DISCONNECT_REASON_ERROR)
				{
					$self->{auto_reconnect_pending} = 0;
					$self->{auto_reconnect_allowed} = 1;
					$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);

					if(defined($self->{disconnect_probe_thread}))
					{
						$self->{disconnect_probe_thread}->join();
						$self->{disconnect_probe_thread} = undef;
					}

					if(defined($IPCONNECTION_SOCKET) && $self->{socket_id} == $socket_id)
					{
						$self->{receive_flag} = undef;

						$IPCONNECTION_SOCKET->shutdown(2);
						$IPCONNECTION_SOCKET->close();
					}

					$IPCONNECTION_SOCKET = undef;

					if(defined($self->{receive_thread}))
					{
						$self->{receive_thread}->join();
						$self->{receive_thread} = undef;
					}

					if(defined($self->{registered_callbacks}->{&CALLBACK_DISCONNECTED}))
					{
						#call the callback with disconnect reason as request
						eval("$self->{registered_callbacks}->{&CALLBACK_DISCONNECTED}(&DISCONNECT_REASON_ERROR)");
					}

					if($self->{auto_reconnect} == 1 &&
					   $self->{auto_reconnect_allowed} == 1 &&
					   $self->{auto_reconnect_pending} == 0)
					{
						$self->{auto_reconnect_pending} = 1;
						$self->_handle_connect(&CONNECT_REASON_AUTO_RECONNECT);
					}

					return 1;
				}

				if($reason == &DISCONNECT_REASON_SHUTDOWN)
				{
					$self->{auto_reconnect_pending} = 0;
					$self->{auto_reconnect_allowed} = 1;
					$self->{disconnect_probe_queue}->enqueue(&_QUEUE_EXIT);

					if(defined($self->{disconnect_probe_thread}))
					{
						$self->{disconnect_probe_thread}->join();
						$self->{disconnect_probe_thread} = undef;
					}

					if(defined($IPCONNECTION_SOCKET) && $self->{socket_id} == $socket_id)
					{
						$self->{receive_flag} = undef;

						$IPCONNECTION_SOCKET->shutdown(2);
						$IPCONNECTION_SOCKET->close();
					}

					$IPCONNECTION_SOCKET = undef;

					if(defined($self->{receive_thread}))
					{
						$self->{receive_thread}->join();
						$self->{receive_thread} = undef;
					}

					if(defined($self->{registered_callbacks}->{&CALLBACK_DISCONNECTED}))
					{
						#call the callback with disconnect reason as request
						eval("$self->{registered_callbacks}->{&CALLBACK_DISCONNECTED}(&DISCONNECT_REASON_SHUTDOWN)");
					}

					if($self->{auto_reconnect} == 1 &&
					   $self->{auto_reconnect_allowed} == 1 &&
					   $self->{auto_reconnect_pending} == 0)
					{
						$self->{auto_reconnect_pending} = 1;
						$self->_handle_connect(&CONNECT_REASON_AUTO_RECONNECT);
					}

					return 1;
				}
			}
		}
	}
	return 1;
}

sub _dispatch_packet
{
	my ($self, $packet) = @_;

	my $uid = $self->_get_uid_from_data($packet);
	my $len = $self->_get_len_from_data($packet);
	my $fid = $self->_get_fid_from_data($packet);
	my $payload = $self->_get_payload_from_data($packet);

	if($fid == &CALLBACK_ENUMERATE)
	{
		if(defined($self->{registered_callbacks}->{&CALLBACK_ENUMERATE}))
		{
			my $form_unpack = 'Z8 Z8 Z C3 C3 S C';
			my @form_unpack_arr = split(' ', $form_unpack);
			my @copy_info_arr;
			my $copy_info_arr_len;
			my $copy_from_index = 0;
			my $arguments_arr_index = 0;
			my $anon_arr_index = 0;
			my @return_arr;
			my @arguments_arr = unpack($form_unpack, $payload);

			if(scalar(@form_unpack_arr) > 1)
			{
				foreach(@form_unpack_arr)
				{
					my $count = $_;
					my @form_single_arr = split('', $_);

					if($form_single_arr[0] eq 'c' ||
					   $form_single_arr[0] eq 'C' ||
					   $form_single_arr[0] eq 's' ||
					   $form_single_arr[0] eq 'S' ||
					   $form_single_arr[0] eq 'l' ||
					   $form_single_arr[0] eq 'L' ||
					   $form_single_arr[0] eq 'q' ||
					   $form_single_arr[0] eq 'Q' ||
					   $form_single_arr[0] eq 'f')
					{
							if(scalar(@form_single_arr) > 1)
							{
								$count =~ s/[^\d]//g;
								push(@copy_info_arr, [$copy_from_index, $count]);
								$copy_from_index += $count;

								next;
							}
							else
							{
								$copy_from_index ++;
							}
					}
					else
					{
						$copy_from_index ++;
					}
				}

				$copy_info_arr_len = scalar(@copy_info_arr);

				if($copy_info_arr_len > 0)
				{
					while($arguments_arr_index < scalar(@arguments_arr))
					{
						if(scalar(@copy_info_arr) > 0)
						{
							if($copy_info_arr[0][0] == $arguments_arr_index)
							{
								my $anon_arr_iterator = $copy_info_arr[0][0];

								if($anon_arr_index == 0)
								{
									$anon_arr_index = $anon_arr_iterator;
								}

								$return_arr[$anon_arr_index] = [];

								for(; $anon_arr_iterator < ($copy_info_arr[0][0]+$copy_info_arr[0][1]); $anon_arr_iterator++)
								{
									push($return_arr[$anon_arr_index], $arguments_arr[$anon_arr_iterator]);
								}

								$anon_arr_index ++;
								$arguments_arr_index += $copy_info_arr[0][1];
								shift(@copy_info_arr);
							}
							else
							{
								push(@return_arr, $arguments_arr[$arguments_arr_index]);
								$anon_arr_index ++;
								$arguments_arr_index ++;
							}
						}
						else
						{
							push(@return_arr, $arguments_arr[$arguments_arr_index]);
							$arguments_arr_index ++;
						}
					}

					my $i = 0;

					foreach(@form_unpack_arr)
					{
						my @form_single_arr = split('', $_);

						if($form_single_arr[0] eq 'a' && scalar(@form_single_arr) > 1)
						{
							my @string_to_split_arr = split('', $return_arr[$i]);
							$return_arr[$i] = [];

							foreach(@string_to_split_arr)
							{
								push($return_arr[$i], $_);
							}
						}
						$i ++;
					}

					eval("$self->{registered_callbacks}->{&CALLBACK_ENUMERATE}(\@return_arr)");

					return 1;
				}

				if($copy_info_arr_len == 0)
				{
					my @return_arr = unpack($form_unpack, $payload);
					my $i = 0;

					foreach(@form_unpack_arr)
					{
						my @form_single_arr = split('', $_);

						if($form_single_arr[0] eq 'a' && scalar(@form_single_arr) > 1)
						{
							my @string_to_split_arr = split('', $return_arr[$i]);
							$return_arr[$i] = [];

							foreach(@string_to_split_arr)
							{
								push($return_arr[$i], $_);
							}
						}
						$i ++;
					}

					eval("$self->{registered_callbacks}->{&CALLBACK_ENUMERATE}(\@return_arr)");
				}
			}

			if(scalar(@form_unpack_arr) == 1)
			{
				my @form_unpack_arr_0_arr = split('', $form_unpack_arr[0]);

				if(scalar(@form_unpack_arr_0_arr) > 1)
				{
					my @unpack_tmp_arr = unpack($form_unpack, $payload);

					if($form_unpack_arr_0_arr[0] eq 'a')
					{
						my @return_arr = split('', $unpack_tmp_arr[0]);
						eval("$self->{registered_callbacks}->{&CALLBACK_ENUMERATE}(\@return_arr)");
					}
					if($form_unpack_arr_0_arr[0] eq 'Z')
					{
						my @return_arr = @unpack_tmp_arr;
						eval("$self->{registered_callbacks}->{&CALLBACK_ENUMERATE}($return_arr[0])");
					}
					my @return_arr = @unpack_tmp_arr;
					eval("$self->{registered_callbacks}->{&CALLBACK_ENUMERATE}(\@return_arr)");
				}
				if(scalar(@form_unpack_arr_0_arr) == 1)
				{
					eval("$self->{registered_callbacks}->{&CALLBACK_ENUMERATE}(unpack($form_unpack, $payload))");
				}
			}
		}
		return 1;
	}

	if(!defined($self->{devices}->{$uid}))
	{
		return 1;
	}

	if(defined($self->{devices}->{$uid}->{super}->{registered_callbacks}->{$fid}))
	{
		my @callback_format_arr = split(' ', $self->{devices}->{$uid}->{callback_formats}->{$fid});

		if(scalar(@callback_format_arr) > 1)
		{
			my @callback_return_arr = unpack($self->{devices}->{$uid}->{callback_formats}->{$fid}, $payload);
			eval("$self->{devices}->{$uid}->{super}->{registered_callbacks}->{$fid}(\@callback_return_arr)");
		}

		if(scalar(@callback_format_arr) == 1)
		{
			my $_payload_unpacked = unpack($self->{devices}->{$uid}->{callback_formats}->{$fid}, $payload);
			eval("$self->{devices}->{$uid}->{super}->{registered_callbacks}->{$fid}($_payload_unpacked)");
		}

		if(scalar(@callback_format_arr) == 0)
		{
			eval("$self->{devices}->{$uid}->{super}->{registered_callbacks}->{$fid}()");
		}
	}

	return 1;
}

sub _disconnect_probe_thread_subroutine
{
	my ($self) = @_;

	my $socket_id = $self->{socket_id};

	while(1)
	{
		my $_disconnect_probe_queue_data = undef;
		$_disconnect_probe_queue_data = $self->{disconnect_probe_queue}->dequeue_timed(&_DISCONNECT_PROBE_INTERVAL);

		if(defined($_disconnect_probe_queue_data) && $_disconnect_probe_queue_data == &_QUEUE_EXIT)
		{
			#exiting thread
			last;
		}
		else
		{
			lock($Tinkerforge::IPConnection::SEND_LOCK);

			my $_disconnect_probe_packet = $self->_create_packet_header(undef, 8, &_FUNCTION_DISCONNECT_PROBE);

			eval
			{
				$| = 1;
				$IPCONNECTION_SOCKET->send($_disconnect_probe_packet);
			};

			if($!)
			{
				$self->{callback_queue}->enqueue([&_QUEUE_META, &CALLBACK_DISCONNECTED, &DISCONNECT_REASON_ERROR, $socket_id]);

				last;
			}
			else
			{
				next;
			}
		}
	}

	return 1;
}

1;
