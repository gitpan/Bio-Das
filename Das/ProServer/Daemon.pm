package Bio::Das::ProServer::Daemon;

=head1 AUTHOR

Tony Cox <avc@sanger.ac.uk>.

Roger Pettett <rmp@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

use strict;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Response;
use Data::Dumper;
use Compress::Zlib;
use CGI;
use Bio::Das::ProServer::Config;

sub new {
  my ($class, $config) = @_;
  my $self = bless {}, $class;
  $self->config($config);
  return $self;
}

sub config {
  my ($self, $config) = @_;
  $self->{'config'} = $config if($config);
  $self->{'config'} ||= Bio::Das::ProServer::Config->new();
  return $self->{'config'};
}

#########
# main control loop
#
sub handle {
  my $self    = shift;
  my $config  = $self->config();
  my $host    = $config->host();
  my $port    = $config->port();
  my $d       = HTTP::Daemon->new(
#				  ReusePort => 1,
				  ReuseAddr => 1,
				  LocalAddr => $host,
				  LocalPort => $port,
				 ) or die "Cannot start daemon: $!\n";

  $self->log("Please contact me at this URL: " . $d->url . "das/dsn/{command}");
  
  $SIG{'CHLD'} = 'IGNORE'; # Reap our forked processes immediately
  
  while (my $c = $d->accept()) {
    
    #########
    # fork to handle request
    #
    my $pid;
    if ($pid = fork) {
      #########
      # I am the parent
      #
      next;

    } elsif (defined $pid) {
      #########
      # I am the child
      #
      $self->log("Child process $$ born...");

    } else {
      die "Nasty forking error: $!\n";
    }

    #########
    # child code - handle the request
    #
    while (my $req = $c->get_request()) {
      
      my $url = $req->uri();
      my $cgi;
      
      #########
      # process the parameters
      #
      if ($req->method() eq 'GET') {
	$cgi = CGI->new($url->query());
	
      } elsif ($req->method() eq 'POST') {
	$cgi = CGI->new($req->{'_content'});
      }
      
      $self->use_gzip(-1); # the default
      
      my $path   = $url->path();
      $self->log("Request: $path");
      $path      =~ /das\/(.*?)\/(.*)/;
      my $dsn    = $1 || "";
      my $method = $2 || "";
      $method    =~ s/^(.*?)\//$1/;

      if ($req->header('Accept-Encoding') && ($req->header('Accept-Encoding') =~ /gzip/) ) {
	$self->use_gzip(1);
	$self->log("  compressing content [client understands gzip content]");
      }
      
      if ($req->method() eq 'GET' || $req->method() eq 'POST') {
	my $res     = HTTP::Response->new();
	my $content = "";
	
	#########
	# unrecognised DSN
	#
	if($path ne "/das/dsn" && !$config->knows($dsn)) {
	  $c->send_error("401", "Bad data source");
	  $c->close();
	  $self->log("Child process $$ exit [Bad data source]");
	  exit; # VERY IMPORTANT - reap the child process!
	}
	
	if  ($path eq "/das/dsn") {
	  $content .= $self->do_dsn_request($res);

	} elsif ($config->adaptor($dsn)->implements($method)) {

	  if($method eq "features") {
	    $content .= $self->do_feature_request($res, $dsn, $cgi);

	  } elsif ($method eq "stylesheet") {
	    $content .= $self->do_stylesheet_request($res, $dsn);

	  } elsif($method eq "dna") {
	    $content .= $self->do_dna_request($res, $dsn, $cgi);

	  } elsif($method eq "entry_points") {
	    $content .= $self->do_entry_points_request($res, $dsn, $cgi);

	  } elsif($method eq "types") {
	    $content .= $self->do_types_request($res, $dsn, $cgi);
	  }

	} else {
	  $c->send_error("501", "Unimplemented feature");
	  $c->close();
	  $self->log("Child process $$ exit [Unimplemented feature]");
	  exit; # VERY IMPORTANT - reap the child process!
	}
	
	if( ($self->use_gzip() == 1) && (length($content) > 10000) ) {
	  $content = $self->gzip_content($content);
	  $res->content_encoding('gzip') if $content;
	  $self->use_gzip(0)
	}
	
	$res->content_length(length($content));
	$res->content($content);
	$c->send_response($res);
	
      } else {
	$c->send_error(RC_FORBIDDEN);
      }
      
      $c->close();
      $self->log("Child process $$ normal exit.");
      exit; # VERY IMPORTANT - reap the child process!
    }
    
    $c->close();
    undef($c);
  }
}

#########
# DAS method: entry_points
#
sub do_entry_points_request {
  my ($self, $res, $dsn, $cgi) = @_;
  
  my $adaptor = $self->adaptor($dsn);
  my $content = $adaptor->open_dasep();
  $content   .= $adaptor->das_entry_points();
  $content   .= $adaptor->close_dasep();

  $self->header($res, $adaptor);
  
  return $content;
}

#########
# DAS method: types
#
sub do_types_request {
  my ($self, $res, $dsn, $cgi) = @_;
  
  my $adaptor = $self->adaptor($dsn);
  my $content = $adaptor->open_dastypes();
  my @segs    = $cgi->param('segment');
  $content   .= $adaptor->das_types({'segments' => \@segs});
  $content   .= $adaptor->close_dastypes();

  $self->header($res, $adaptor);
  
  return $content;
}

#########
# DAS method: features/1.0
#
sub do_feature_request {
  my ($self, $res, $dsn, $cgi) = @_;
  
  my $adaptor  = $self->adaptor($dsn);
  my $content  = $adaptor->open_dasgff();
  my @segs     = $cgi->param('segment');
  my @features = $cgi->param('feature_id');

  for my $segment (@segs) {
    $self->log("  segment ===> $segment");
  }

  $content .= $adaptor->das_features({
				      'segments' => \@segs,
				      'features' => \@features,
				     });
  $content .= $adaptor->close_dasgff();

  $self->header($res, $adaptor);
  
  return $content;
}

#########
# DAS method: dna / sequence
#
sub do_dna_request {
  my ($self, $res, $dsn, $cgi) = @_;
  
  my $adaptor = $self->adaptor($dsn);
  my $content = $adaptor->open_dassequence();
  my @segs    = $cgi->param('segment');

  for my $segment (@segs) {
    $self->log("  segment ===> $segment");
  }

  $content .= $adaptor->das_dna(\@segs);
  $content .= $adaptor->close_dassequence();

  $self->header($res, $adaptor);
  
  return $content;
}

#########
# DAS method: dsn
#
sub do_dsn_request {
  my ($self, $res) = @_;
  
  my $adaptor = $self->adaptor();
  my $content = $adaptor->das_dsn();
  $self->header($res, $adaptor);
  
  return $content;
}

#########
# DAS method: stylesheet
#
sub do_stylesheet_request {
  my ($self, $res, $dsn) = @_;
  
  my $adaptor = $self->adaptor($dsn);
  my $content = $adaptor->das_stylesheet();
  $self->header($res, $adaptor);
  
  return $content;
}

#########
# DAS/HTTP headers
#
sub header {
  my ($self, $response, $adaptor, $code) = @_;
  my $config = $self->config();

  $response->code($code || "200 OK"); # is this the right format?
  $response->header('Content-Type'       => 'text/plain');
  $response->header('X_DAS_Version'      => $config->das_version());
  $response->header('X_DAS_Status'       => $code || "200 OK");
  $response->header('X_DAS_Capabilities' => $adaptor->das_capabilities());
}

#########
# handle gzipped content
#
sub gzip_content {
  my ($self, $content) = @_;

  if($content && $self->use_gzip()) {
    my $d = Compress::Zlib::memGzip($content);
    return $d if ($d);

    warn ("Content compression failed: $!\n");
    return(undef);

  } else {
    warn ("Inconsistent request for gzip content\n");
  }
}

#########
# gzip on/off helper
#
sub use_gzip {
  my ($self, $var)    = @_;
  $self->{'use_gzip'} = $var if($var);
  return($self->{'use_gzip'});
}

#########
# return an appropriate adaptor object given a DSN
#
sub adaptor {
  my ($self, $dsn) = @_;
  return $self->config->adaptor($dsn);
}

#########
# debug log
#
sub log {
  my ($self, @messages) = @_;
  for my $m (@messages) {
    print STDERR "$m\n";
  }
}

1;
