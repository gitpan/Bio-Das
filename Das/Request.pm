package Bio::Das::Request;
# encapsulates a request on a DAS server
# also knows how to deal with response
# $Id: Request.pm,v 1.5 2002/08/31 23:32:53 lstein Exp $

use strict;
require 5.6.0;  # because of indirect method calls

use Bio::Das::Util;
use HTML::Parser;
use Compress::Zlib;
use Carp 'croak','confess';

use constant GZIP_MAGIC => 0x1f8b;
use constant OS_MAGIC => 0x03;
use constant DASVERSION => 0.95;

use overload '""' => 'url';

# -dsn      dsn object
# -args     e.g. { segment => [qw(ZK154 M7 CHROMOSOME_I:1000000,2000000)] }
# -callback code ref to be invoked when each "object" is finished parsing
sub new {
  my $package = shift;
  my ($dsn,$args,$callback) = rearrange(['dsn',
					 'args',
					 'callback'
					],@_);
  $dsn = Bio::Das::DSN->new($dsn) unless ref $dsn;
  return bless {
		dsn       => $dsn,
		args      => $args,
		callback  => $callback,
		results   => [],         # list of objects to return
		p_success           => 0,
		p_error             => '',
		p_compressed_stream => 0,
		p_xml_parser        => undef,
	       },$package;
}

# ==  to be overridden in subclasses ==
# provide the command name (e.g. 'types')
sub command {
  my $self = shift;
  die "command() must be implemented in subclass";
}

# create an initiliazed HTML::Parser object
sub create_parser {
  my $self = shift;
  my $parser= HTML::Parser->new(
				api_version   => 3,
				start_h       => [ sub { $self->tag_starts(@_) },'tagname,attr' ],
				end_h         => [ sub { $self->tag_stops(@_)  },'tagname' ],
				text_h        => [ sub { $self->char_data(@_)  },  'dtext' ],
			       );

}

# tags will be handled by a method named t_TAGNAME
sub tag_starts {
  my $self = shift;
  my ($tag,$attrs) = @_;
  my $method = "t_$tag";
  $self->{char_data} = '';  # clear char data
  eval {$self->$method($attrs)};   # indirect method call
}

# tags will be handled by a method named t_TAGNAME
sub tag_stops {
  my $self = shift;
  my $tag = shift;
  my $method = "t_$tag";
  $self->$method() if $self->can($method);
}

sub char_data {
  my $self = shift;
  if (my $text = shift) {
    $self->{char_data} .= $text;
  } else {
    $self->trim($self->{char_data});
  }
}

sub cleanup {
  my $self = shift;
}

# == Generate the URL request ==
sub url {
  my $self = shift;
  my $url     = $self->dsn->url;
  my $command = $self->command;

  if (defined $command) {
    $url .= "/$command";
  }

  $url;
}

sub clear_results {
  shift->{results} = [];
}

sub results {
  my $self = shift;
  my $r = $self->{results} or return;
  return @$r;
}

# add one or more objects to our results list
sub add_object {
  my $self = shift;
  if (my $cb = $self->callback) {
    eval {$cb->(@_)} or warn "$@";
  } else {
    push @{$self->{results}},@_;
  }
}

# == status ==

# after the request is finished, is_success() will return true if successful
sub is_success { shift->success; }

# error() will give the most recent error message
sub error {
  my $self = shift;
  if (@_) {
    $self->{p_error} = shift;
    return;
  } else {
    return $self->{p_error};
  }
}

# == ACCESSORS ==

# get/set the HTML::Parser object
sub xml_parser {
  my $self = shift;
  my $d = $self->{p_xml_parser};
  $self->{p_xml_parser} = shift if @_;
  $d;
}

# get/set stream compression flag
sub compressed {
  my $self = shift;
  my $d = $self->{p_compressed_stream};
  $self->{p_compressed_stream} = shift if @_;
  $d;
}

# get/set success flag
sub success {
  my $self = shift;
  my $d = $self->{p_success};
  $self->{p_success} = shift if @_;
  $d;
}

# get/set callback
sub callback {
  my $self = shift;
  my $d = $self->{callback};
  $self->{callback} = shift if @_;
  $d;
}

# get/set the DSN
sub dsn {
  my $self = shift;
  my $d = $self->{dsn};
  $self->{dsn} = shift if @_;
  $d;
}

# get/set the request arguments
sub args {
  my $self = shift;
  my $d = $self->{args};
  $self->{args} = shift if @_;
  $d;
}

# return the method - currently "auto"
sub method {
  my $self = shift;
  return 'auto';
}

# == Parser stuff ==

# handle the headers
sub headers {
  my $self    = shift;
  my $hashref = shift;

  # check the DAS header
  my $protocol = $hashref->{'X-Das-Version'} or
    return $self->error('no X-Das-Version header');

  my ($version) = $protocol =~ m!(?:DAS/)?([\d.]+)! or
    return $self->error('invalid X-Das-Version header');

  $version >= DASVERSION or
    return $self->error("DAS server is too old. Got $version; require at least ${\DASVERSION}");

  # check the DAS status
  my $status = $hashref->{'X-Das-Status'} or
    return $self->error('no X-Das-Status header');

  $status == 200 or
    return $self->error("DAS reported error code $status");

  $self->compressed(1) if $hashref->{'Content-Encoding'} =~ /gzip/;

  1;  # we passed the tests, so we continue to parse
}

# called to do initialization after receiving the header
# but before processing any body data
sub start_body {
  my $self = shift;
  $self->xml_parser($self->create_parser);
  $self->xml_parser->xml_mode(1);
  return $self->xml_parser;
}

# called to process body data
sub body {
  my $self = shift;
  my $data = shift;
  my $parser = $self->xml_parser or return;
  my $status;
  if ($self->compressed) {
    ($data,$status) = $self->inflate($data);
    return unless $status;
  }
  return $parser->parse($data);
}

# called to finish body data
sub finish_body {
  my $self = shift;
  my $parser = $self->xml_parser or return;
  my $result = $parser->eof;
  $self->success(1);
  1;
}

# == inflation stuff ==
sub inflate {
  my $self = shift;
  my $compressed_data = shift;

  # the complication here is that we might be called on a portion of the
  # data stream that contains only a partial header.  This is unlikely, but
  # I'll be paranoid.
  if (!$self->{p_i}) { # haven't created the inflator yet
    $self->{p_gzip_header} .= $compressed_data;
    my $cd = $self->{p_gzip_header};
    return ('',1) if length $cd < 10;

    # process header
    my ($gzip_magic,$gzip_method,$comment,$time,undef,$os_magic) 
      = unpack("nccVcc",substr($cd,0,10));

    return $self->error("invalid gzip stream")        unless $gzip_magic == GZIP_MAGIC;
    return $self->error("unknown compression method") unless $gzip_method == Z_DEFLATED;

    substr($cd,0,10) = '';     # truncate the rest

    # handle embedded comments that proceed deflated stream
    # note that we do not correctly buffer here, but assume
    # that we've got it all.  We don't bother doing this right,
    # because the filename field is not usually present in
    # the on-the-fly streaming done by HTTP servers.
    if ($comment == 8 or $comment == 10) {
      my ($fname) = unpack("Z*",$cd);
      substr($cd,0,(length $fname)+1) = '';
    }

    $compressed_data = $cd;
    delete $self->{p_gzip_header};

    $self->{p_i} = inflateInit(-WindowBits => -MAX_WBITS() ) or return;
  }

  my ($out,$status) = $self->{p_i}->inflate($compressed_data);
  return $self->error("inflation failed, errcode = $status")
    unless $status == Z_OK or $status == Z_STREAM_END;

  return ($out,1);
}

# utilities
sub trim {
  my $self = shift;
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  $string;
}

1;
