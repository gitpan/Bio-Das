package Bio::Das::Parser;
# this is the base class that implements the methods expected by
# Bio::Das::HTTP::Fetch
# $Id: Parser.pm,v 1.1.1.1 2001/08/19 16:01:38 lstein Exp $

use strict;
use HTML::Parser;
use Compress::Zlib;
use Carp 'croak';

use constant GZIP_MAGIC => 0x1f8b;
use constant OS_MAGIC => 0x03;
use constant DASVERSION => 0.95;

sub new {
  my $package = shift;
  my $self = bless {
		    p_success           => 0,
		    p_error             => '',
		    p_compressed_stream => 0,
		    p_xml_parser        => undef,
		   },$package;   # set the outcome flag to false
  $self;
}

sub xml_parser {
  my $self = shift;
  my $d = $self->{p_xml_parser};
  $self->{p_xml_parser} = shift if @_;
  $d;
}

sub compressed {
  my $self = shift;
  my $d = $self->{p_compressed_stream};
  $self->{p_compressed_stream} = shift if @_;
  $d;
}

sub success {
  my $self = shift;
  my $d = $self->{p_success};
  $self->{p_success} = shift if @_;
  $d;
}

sub is_success { shift->success; }

sub error {
  my $self = shift;
  if (@_) {
    $self->{p_error} = shift;
    return;
  } else {
    return $self->{p_error};
  }
}

# handle the headers
sub headers {
  my $self    = shift;
  my $hashref = shift;

  # check the DAS header
  my $protocol = $hashref->{'X-Das-Version'} or
    return $self->error('no X-Das-Version header');

  my ($version) = $protocol =~ m!DAS/([\d.]+)! or
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

# supposed to be implemented by subclass
sub create_parser {
  croak "the create_parser() must be overridden in subclasses";
}

############################### inflation stuff ############################
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


1;
