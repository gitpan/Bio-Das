#########
# Author: rmp
# Maintainer: rmp
# Created: 2003-05-20
# Last Modified: 2003-06-11
# Generic SourceAdaptor. Generates XML and manages callouts for DAS functions
#
package Bio::Das::ProServer::SourceAdaptor;

=head1 AUTHOR

Roger Pettett <rmp@sanger.ac.uk>.

Based on AGPServer by

Tony Cox <avc@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

use strict;

sub new {
  my ($class, $defs) = @_;
  my $self = {
	      'dsn'          => $defs->{'dsn'},
	      'port'         => $defs->{'port'},
	      'hostname'     => $defs->{'hostname'},
	      'config'       => $defs->{'config'},
	      '_data'        => {},
	      '_sequence'    => {},
	      '_features'    => {},
	      'capabilities' => {
				 'dsn' => "1.0",
				},
	     };

  bless $self, $class;
  $self->init($defs);
  return $self;
}

sub init       {};

sub dsn {
  my $self = shift;
  return $self->{'dsn'} || "unknown";
};

sub dsnversion {
  my $self = shift;
  return $self->{'dsnversion'} || "1.0";
};

sub start {
  1;
}

sub end {
  my $self = shift;
  return $self->length(@_);
}

#########
# build the relevant transport configured for this adaptor
#
sub transport {
  my $self = shift;
  if(!exists $self->{'_transport'}) {

    my $transport = "Bio::Das::ProServer::SourceAdaptor::Transport::".$self->config->{'transport'};
    eval "require $transport";
    warn $@ if($@);
    $self->{'_transport'} = $transport->new({
					     'config' => $self->config(),
					    });
  }
  return $self->{'_transport'};
}

#########
# config settings for this adaptor
#
sub config {
  my ($self, $config) = @_;
  $self->{'config'}   = $config if($config);
  return $self->{'config'};
}

#########
# helper use to determine if an adaptor implements a request
#
sub implements {
  my ($self, $method) = @_;
  return exists $self->{'capabilities'}->{$method};
}

#########
# capabilities header support
#
sub das_capabilities {
  my $self = shift;
  return join('; ', map { "$_/$self->{'capabilities'}->{$_}" } keys %{$self->{'capabilities'}});
}

#########
# dsn response
#
sub das_dsn {
  my $self    = shift;
  my $port    = $self->{'port'};
  my $host    = $self->{'hostname'};
  my $content = $self->open_dasdsn();
  
  for my $adaptor ($self->config->adaptors()) {
    my $dsn        = $adaptor->dsn();
    my $dsnversion = $adaptor->dsnversion();
    $content .= qq(  <DSN>
    <SOURCE id="$dsn" version="$dsnversion">$dsn</SOURCE>
    <MAPMASTER>http://$host:$port/das/$dsn/</MAPMASTER>
    <DESCRIPTION>$dsn feature annotation</DESCRIPTION>
  </DSN>\n);
  }
  
  $content .= $self->close_dasdsn();
  
  return ($content);
}

#########
# open dsn response
#
sub open_dasdsn {
  qq(<?xml version="1.0" standalone="no"?>
<!DOCTYPE DASDSN SYSTEM 'http://www.biodas.org/dtd/dasdsn.dtd' >
<DASDSN>\n);
}

#########
# close dsn response
#
sub close_dasdsn {
  qq(</DASDSN>\n);
}

#########
# open features response
#
sub open_dasgff {
  my ($self) = @_;
  my $host   = $self->{'hostname'};
  my $port   = $self->{'port'};
  my $dsn    = $self->dsn();

  return qq(<?xml version="1.0" standalone="yes"?>
<!DOCTYPE DASGFF SYSTEM "http://www.biodas.org/dtd/dasgff.dtd">
<DASGFF>
  <GFF version="1.01" href="http://$host:$port/das/$dsn/features">\n);
}

#########
# close features response
#
sub close_dasgff {
  qq(  </GFF>
</DASGFF>\n);
}

#########
# hook for optimising results to be returned.
# default - do nothing
# Not necessary for most circumstances, but useful for deciding on what sort
# of coordinate system you return the results if more than one type is available.
#
sub init_segments {
}

#########
# features response
#
sub das_features {
  my ($self, $opts) = @_;
  my $response      = "";

  $self->init_segments($opts->{'segments'});

  #########
  # straight features
  #
  for my $seg (@{$opts->{'segments'}}) {
    my ($seg, $coords) = split(':', $seg);
    my ($start, $end)  = split(',', $coords||"");
    my $segstart       = $start || $self->start($seg) || "";
    my $segend         = $end   || $self->end($seg)   || "";
    $response         .= qq(    <SEGMENT id="$seg" version="1.0" start="$segstart" stop="$segend">\n);

    for my $feature ($self->build_features({
					    'segment'   => $seg,
					    'start'     => $start,
					    'end'       => $end,
					   }  )) {
      my $start    = $feature->{'start'}        || "0";
      my $end      = $feature->{'end'}          || "0";
      my $note     = $feature->{'note'}         || "";
      my $id       = $feature->{'id'}           || "";
      my $type     = $feature->{'type'}         || "";
      my $method   = $feature->{'method'}       || "";
      my $group    = $feature->{'group'}        || "";
      my $score    = $feature->{'score'}        || "";
      my $ori      = $feature->{'ori'}          || "0";
      my $phase    = $feature->{'phase'}        || "";
      my $link     = $feature->{'link'}         || "";
      my $linktxt  = $feature->{'linktxt'}      || $link;
      my $tst      = $feature->{'target_start'} || "";
      my $tend     = $feature->{'target_stop'}  || "";
      my $cat      = (defined $feature->{'typecategory'})?qq(category="$feature->{'typecategory'}"):"";
      my $subparts = $feature->{'typesubparts'}    || "no";
      my $supparts = $feature->{'typessuperparts'} || "no";
      my $ref      = $feature->{'typesreference'}  || "no";
#      $response   .= qq(    <SEGMENT id="$seg" version="1.0" start="$start" stop="$end">\n);
      $response   .= qq(      <FEATURE id="$id" label="$id">\n);
      $response   .= qq(        <TYPE id="$type" $cat reference="$ref" subparts="$subparts" superparts="$supparts">$type</TYPE>\n);
      $response   .= qq(        <METHOD id="$method">$method</METHOD>\n) if($method ne "");
      $response   .= qq(        <START>$start</START>\n);
      $response   .= qq(        <END>$end</END>\n);
      $response   .= qq(        <SCORE>$score</SCORE>\n)                 if($score ne "");
      $response   .= qq(        <ORIENTATION>$ori</ORIENTATION>\n)       if($ori   ne "");
      $response   .= qq(        <PHASE>$phase</PHASE>\n)                 if($phase ne "");
      $response   .= qq(        <NOTE>$note</NOTE>\n)                    if($note  ne "");
      $response   .= qq(        <GROUP id="$group" />\n)                 if($group ne "");
      $response   .= qq(        <LINK href="$link">$linktxt</LINK>\n)    if($link  ne "");
      $response   .= qq(        <TARGET id="$id" start="$tst" stop="$tend" />\n) if($tst ne "" && $tend ne "");
      $response   .= qq(      </FEATURE>\n);
#      $response   .= qq(    </SEGMENT>\n);
    }
    $response .= qq(    </SEGMENT>\n);
  }

  #########
  # features by id
  #
  for my $fid (@{$opts->{'features'}}) {
    for my $feature ($self->build_features({
					    'feature'   => $fid,
					   })) {
      my $seg      = $feature->{'segment'}      || "";
      my $start    = $feature->{'start'}        || "";
      my $end      = $feature->{'end'}          || "";
      my $note     = $feature->{'note'}         || "";
      my $id       = $feature->{'id'}           || "";
      my $type     = $feature->{'type'}         || "unknown";
      my $method   = $feature->{'method'}       || "";
      my $group    = $feature->{'group'}        || "";
      my $score    = $feature->{'score'}        || "";
      my $ori      = $feature->{'ori'}          || "0";
      my $phase    = $feature->{'phase'}        || "";
      my $link     = $feature->{'link'}         || "";
      my $linktxt  = $feature->{'linktxt'}      || $link;
      my $tst      = $feature->{'target_start'} || "";
      my $tend     = $feature->{'target_stop'}  || "";
      my $cat      = (defined $feature->{'typecategory'})?qq(category="$feature->{'typecategory'}"):"";
      my $subparts = $feature->{'typesubparts'}    || "no";
      my $supparts = $feature->{'typessuperparts'} || "no";
      my $ref      = $feature->{'typesreference'}  || "no";
      $response   .= qq(    <SEGMENT id="$seg" version="1.0" start="$start" stop="$end">\n);
      $response   .= qq(      <FEATURE id="$id" label="$id">\n);
      $response   .= qq(        <TYPE id="$type" $cat reference="$ref" subparts="$subparts" superparts="$supparts">$type</TYPE>\n);
      $response   .= qq(        <METHOD id="$method">$method</METHOD>\n) if($method ne "");
      $response   .= qq(        <START>$start</START>\n);
      $response   .= qq(        <END>$end</END>\n);
      $response   .= qq(        <SCORE>$score</SCORE>\n)                 if($score ne "");
      $response   .= qq(        <ORIENTATION>$ori</ORIENTATION>\n)       if($ori   ne "");
      $response   .= qq(        <PHASE>$phase</PHASE>\n)                 if($phase ne "");
      $response   .= qq(        <NOTE>$note</NOTE>\n)                    if($note  ne "");
      $response   .= qq(        <GROUP id="$group" />\n)                 if($group ne "");
      $response   .= qq(        <LINK href="$link">$linktxt</LINK>\n)    if($link  ne "");
      $response   .= qq(        <TARGET id="$id" start="$tst" stop="$tend" />\n) if($tst ne "" && $tend ne "");
      $response   .= qq(      </FEATURE>\n);
      $response   .= qq(    </SEGMENT>\n);
    }
  }
  return $response;
}

#########
# open dna/sequence response
#
sub open_dassequence {
  qq(<?xml version="1.0" standalone="no"?>
<!DOCTYPE DASDNA SYSTEM "http://www.wormbase.org/dtd/dasdna.dtd">
<DASDNA>\n);
}

#########
# dna/sequence response
#
sub das_dna {
  my ($self, $segref) = @_;

  my $response = "";
  for my $seg (@$segref) {
    my ($seg, $coords) = split(':', $seg);
    my ($start, $end)  = split(',', $coords||"");
    my $segstart       = $start || $self->start($seg) || "";
    my $segend         = $end   || $self->end($seg)   || "";
    my $sequence       = $self->sequence({
					  'segment' => $seg,
					  'start'   => $start,
					  'end'     => $end,
					 });
    my $seq            = $sequence->{'seq'};
    my $moltype        = $sequence->{'moltype'};
    my $len            = CORE::length($seq);
    $response .= qq(  <SEQUENCE id="$seg" start="$segstart" stop="$segend" moltype="$moltype" version="1.0">\n);
    $response .= qq(    <DNA length="$len">\n      $seq\n);
    $response .= qq(    </DNA>\n);
#    $response .= "$seq\n";
    $response .= qq(  </SEQUENCE>\n);
  }
  return $response;
}

sub open_dastypes {
  my $self = shift;
  my $host = $self->{'hostname'};
  my $port = $self->{'port'};
  my $dsn  = $self->dsn();
  qq(<?xml version="1.0" standalone="no"?>
<!DOCTYPE DASTYPES SYSTEM "http://www.biodas.org/dtd/dastypes.dtd">
<DASTYPES>
  <GFF version="1.0" href="http://$host:$port/das/$dsn/types">\n);
}

sub close_dastypes {
  qq(</GFF>
</DASTYPES>\n);
}

#########
# types response
#
sub das_types {
  my ($self, $opts) = @_;

  my $response = "";
  for my $seg (@{$opts->{'segments'}}) {
    my ($seg, $coords) = split(':', $seg);
    my ($start, $end)  = split(',', $coords||"");
    my $segstart       = $start || $self->start($seg) || "";
    my $segend         = $end   || $self->end($seg)   || "";

    $response .= qq(  <SEGMENT id="$seg" start="$segstart" stop="$segend" version="1.0">\n);
    for my $type ($self->build_types({
				      'segment' => $seg,
				      'start'   => $start,
				      'end'     => $end,
				     })) {
      my $method = qq(method="$type->{'method'}") if(defined $type->{'method'});
      $response .= qq(    <TYPE id="$type->{'type'}" $method>$type->{'count'}</type>\n);
    }
    $response .= qq(  </SEGMENT>\n);
  }
  return $response;
}

#########
# close dna/sequence response
#
sub close_dassequence {
  qq(</DASDNA>\n);
}

#########
# open entrypoints response
#
sub open_dasep {
  my ($self)   = @_;
  my $dsn      = $self->dsn();
  my $host     = $self->{'hostname'};
  my $port     = $self->{'port'};

  return qq(<?xml version="1.0" standalone="no"?>
<!DOCTYPE DASEP SYSTEM "http://www.biodas.org/dtd/dasep.dtd">
<DASEP>
  <ENTRY_POINTS href="http://$host:$port/das/$dsn/entry_points" version="1.0">\n);
}

#########
# close entrypoints response
#
sub close_dasep {
  qq(  </ENTRY_POINTS>
</DASEP>\n);
}

sub das_entry_points {
  my $self    = shift;
  my $content = "";
  
  for my $seg ($self->build_entry_points()) {
    my $subparts = $seg->{'subparts'} || "yes"; # default to yes here as we're giving entrypoints
    $content .= qq(    <SEGMENT id="$seg->{'segment'}" size="$seg->{'length'}" subparts="$subparts" />\n);
  }
  
  return $content;
}



#########
# default stylesheet response
#
sub das_stylesheet {
  qq(<!DOCTYPE DASSTYLE SYSTEM "http://www.biodas.org/dtd/dasstyle.dtd">
<DASSTYLE>
<STYLESHEET version="1.0">
  <CATEGORY id="default">
    <TYPE id="default">
      <GLYPH>
        <BOX>
          <FGCOLOR>black</FGCOLOR>
          <FONT>sanserif</FONT>
          <BUMP>0</BUMP>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
  </CATEGORY>
</STYLESHEET>
</DASSTYLE>\n);
}

1;
