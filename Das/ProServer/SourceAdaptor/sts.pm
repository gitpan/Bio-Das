#########
# Author: jc3
# Maintainer: jc3
# Created: 2003-06-20
# Last Modified: 2003-06-20
# Provides DAS features for SNP information.

package Bio::Das::ProServer::SourceAdaptor::sts;

=head1 AUTHOR

Jody Clements <jc3@sanger.ac.uk>.

based on modules by 

Roger Pettett <rmp@sanger.ac.uk>.

Copyright (c) 2003 The Sanger Institute

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

BEGIN {
  my $root = $ENV{'ENS_ROOT'};
  if(!defined $ENV{'ENSEMBL_SPECIES'} || $ENV{'ENSEMBL_SPECIES'} eq ""){
    print STDERR qq(No species defined... default to Homo_sapiens\n);
    $ENV{'ENSEMBL_SPECIES'} = "Homo_sapiens" ;
  }
  print STDERR qq(species = $ENV{'ENSEMBL_SPECIES'}\n);
  unshift(@INC,"$root/modules");
  unshift(@INC,"$root/ensembl/modules");
  unshift(@INC,"$root/ensembl-draw/modules");
  unshift(@INC,"$root/ensembl-compara/modules");
  unshift(@INC,"$root/ensembl-external/modules");
  unshift(@INC,"$root/conf");
  unshift(@INC,"$root/perl");
  unshift(@INC,"$root/bioperl-live");
}

use strict;
use EnsWeb;
use EnsEMBL::DB::Core;
use base qw(Bio::Das::ProServer::SourceAdaptor);

sub init{
  my $self = shift;
  $self->{'capabilities'} = {
			     'features'   => '1.0',
			     'stylesheet' => '1.0',
			    };
  $self->{'link'} = "http://intweb.sanger.ac.uk/cgi-bin/humace/snp_report.pl?sts=";
  $self->{'linktxt'} = "more information";
}

sub init_segments{
  my ($self,$segments) = @_;
  if (scalar @$segments > 1 && (grep {$_ =~ /^AL\d{6}/i} @$segments)){
    @$segments = grep {$_ !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])/i} @$segments;
  }
}

sub length{
  my ($self,$seg) = @_;
  if ($seg !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    if ($seg !~/^\w+\.\w+\.\w+\.\w+$/i){
      #get contig coordinates
      if (!$self->{'_length'}->{$seg}){
	my $databases = &EnsEMBL::DB::Core::get_databases('core');
	my $ca = $databases->{'core'}->get_CloneAdaptor();
	my $clone = $ca->fetch_by_name($seg);
	my $contigs = $clone->get_all_Contigs();
	if(@$contigs == 1){
	  $self->{'_length'}->{$seg} = $contigs->[0]->length();
	}
      }
      return $self->{'_length'}->{$seg};
    }
    return;
  }
  #get chromosome coordinates
  if (!$self->{'_length'}->{$seg}){
    my $databases = &EnsEMBL::DB::Core::get_databases('lite');
    my $ca = $databases->{'lite'}->get_ChromosomeAdaptor();
    my $chromosome = $ca->fetch_by_chr_name($seg);
    $self->{'_length'}->{$seg} = $chromosome->length();
  }
  return $self->{'_length'}->{$seg};
}


sub das_stylesheet{
  my ($self) = @_;

  my $response = qq(<!DOCTYPE DASSTYLE SYSTEM "http://www.biodas.org/dtd/dasstyle.dtd">
<DASSTYLE>
<STYLESHEET version="1.0">
  <CATEGORY id="sts">
    <TYPE id="Fail">
      <GLYPH>
        <BOX>
          <FGCOLOR>red</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="Pass">
      <GLYPH>
        <BOX>
          <FGCOLOR>green</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="default">
      <GLYPH>
        <BOX>
          <FGCOLOR>darkolivegreen</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
  </CATEGORY>
</STYLESHEET>
</DASSTYLE>\n);

  return $response;
}

sub build_features{
  my ($self,$opts) = @_;
  my $segid  = $opts->{'segment'};
  my $start = $opts->{'start'};
  my $end   = $opts->{'end'};
  my $restriction = "";
  my $query       = "";
  my @features = ();

  if (defined $start && !$end){
    return @features;
  }

  if (defined $start && defined $end){
    $restriction = qq(AND (ms.start_coordinate + ssm.start_coordinate -1) BETWEEN '$start' AND '$end');
  }

  if ($segid =~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    #get chromosome coordinates
    $query = qq(SELECT ms.id_sts,
       (ms.start_coordinate + ssm.start_coordinate -1) as start_coord,
       (ms.end_coordinate + ssm.start_coordinate -1) as end_coord,
       ss.sts_name,
       ss.id_sts as sts_id,
       length(ss.sense_oligoprimer) as sen_len,
       length(ss.antisense_oligoprimer) as anti_len,
       ss.pass_status,
       ms.is_revcomp as ori
       FROM   chrom_seq cs,
       seq_seq_map ssm,
       mapped_sts ms,
       sts_summary ss
       WHERE  cs.database_seqname = '$segid'
       AND    cs.is_current = 1		
       AND    ssm.id_chromseq = cs.id_chromseq
       AND    ms.id_sequence = ssm.sub_sequence
       AND    ss.assay_type = 8
       AND    ss.id_sts = ms.id_sts
       $restriction
       ORDER BY start_coord);
}
  elsif ($segid !~ /^\w+\.\w+\.\w+\.\w+$/i){
    #get contig coordinates
    $query = qq(SELECT 	distinct ssum.sts_name,
	     ssum.id_sts as sts_id,
	     length(ssum.sense_oligoprimer) as sen_len,
	     length(ssum.antisense_oligoprimer) as anti_len,
	     ssum.pass_status,
	     --start_coord,
	     (1 +(csm.contig_orientation * (ms.start_coordinate 
             - csm.start_coordinate))) as start_coord,
	     --end_coord
	     (1 +(csm.contig_orientation * (ms.end_coordinate -
	     csm.start_coordinate))) as end_coord
	     FROM	clone_seq cs,
	     clone_seq_map csm,
	     snp_sequence ss,
	     mapped_sts ms,
	     sts_summary ssum
	     WHERE (ms.start_coordinate BETWEEN csm.start_coordinate
                    AND csm.end_coordinate
	     OR	ms.start_coordinate BETWEEN csm.end_coordinate
                                    AND csm.start_coordinate)
	     AND	cs.database_seqname = '$segid'
	     AND	cs.id_cloneseq = csm.id_cloneseq
	     AND        cs.is_current = 1
	     AND	csm.id_sequence = ms.id_sequence
             AND        ssum.assay_type = 8
	     AND	ms.id_sts = ssum.id_sts
	     ORDER BY start_coord);

  }
  else{
    return @features;
  }
  my $ref = $self->transport->query($query);


  for my $row (@$ref){
    my $url = $self->{'link'};
    my $link = $url . $row->{'STS_ID'};
    my $sen_end = $row->{'START_COORD'} + $row->{'SEN_LEN'} - 1;
    my $anti_start = $row->{'END_COORD'} - $row->{'ANTI_LEN'} - 1;
    my $type = "unknown";
    if ($row->{'PASS_STATUS'} == 1){
      $type = "Pass";
    }
    elsif ($row->{'PASS_STATUS'} == 2){
      $type = "Fail";
    }
    push @features, {
		     'id'      => $row->{'STS_ID'},
		     'ori'     => $row->{'ORI'},
		     'type'    => $type,
		     'method'  => "sts",
		     'start'   => $row->{'START_COORD'},
		     'end'     => $sen_end,
		     'link'    => $link,
		     'linktxt' => $self->{'linktxt'},
		     'typecategory' => "sts",
		    };
    push @features, {
		     'id'      => $row->{'STS_ID'},
		     'ori'     => $row->{'ORI'},
		     'type'    => $type,
		     'method'  => "sts",
		     'start'   => $anti_start,
		     'end'     => $row->{'END_COORD'},
		     'link'    => $link,
		     'linktxt' => $self->{'linktxt'},
		     'typecategory' => "sts",
		    };
  }

  return @features;
}

1;
