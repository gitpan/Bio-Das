#########
# Author: jc3
# Maintainer: jc3
# Created: 2003-06-20
# Last Modified: 2003-06-20
# Provides DAS features for SNP information.

package Bio::Das::ProServer::SourceAdaptor::snp;

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
  unshift(@INC,"$root/ensembl-map/modules");
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
			     'features' => '1.0',
			     'stylesheet' => '1.0',
			    };
  $self->{'link'} = "http://intweb.sanger.ac.uk/cgi-bin/humace/snp_report.pl?snp=";
  $self->{'linktxt'} = "more information";
}

sub length{
  my ($self,$seg) = @_;
  if ($seg !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    #get contig coordinates
    return;
  }
  if (!$self->{'_length'}->{$seg}){
    my $databases = &EnsEMBL::DB::Core::get_databases('core');
    my $ca = $databases->{'core'}->get_ChromosomeAdaptor();
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
   <CATEGORY id="snp">
    <TYPE id="External Verified">
      <GLYPH>
        <BOX>
          <FGCOLOR>red</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="Sanger Verified">
      <GLYPH>
        <BOX>
          <FGCOLOR>green</FGCOLOR>
          <FONT>sanserif</FONT>
          <BGCOLOR>black</BGCOLOR>
        </BOX>
      </GLYPH>
    </TYPE>
    <TYPE id="Two-Hit">
      <GLYPH>
        <BOX>
          <FGCOLOR>blue</FGCOLOR>
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
  my @features = ();
  if (!$end){
    return @features;
  }

my $query = qq(SELECT distinct
       (mapped_snp.position + seq_seq_map.START_COORDINATE -1) as snppos,
       mapped_snp.id_snp as snp_id,
       snp_name.snp_name as snp_name,
       snp.is_confirmed as status
FROM chrom_seq,
     seq_seq_map,
     snp_sequence,
     mapped_snp,
     snp_name,
     snp,
     database_dict
WHERE chrom_seq.DATABASE_SEQNAME='$segid'
AND chrom_seq.ID_CHROMSEQ = seq_seq_map.ID_CHROMSEQ
AND snp_sequence.ID_SEQUENCE = seq_seq_map.SUB_SEQUENCE
AND mapped_snp.ID_SEQUENCE = snp_sequence.ID_SEQUENCE
AND snp_name.id_snp = mapped_snp.id_snp
AND snp.id_snp = snp_name.id_snp
AND snp_name.snp_name_type = 1
AND chrom_seq.DATABASE_SOURCE = database_dict.ID_DICT
AND database_dict.DATABASE_NAME = 'NCBI'
AND database_dict.DATABASE_VERSION = '33'
AND (mapped_snp.position + seq_seq_map.START_COORDINATE -1) BETWEEN '$start' AND '$end'
ORDER BY SNPPOS);

 my $snp = $self->transport->query($query);


for my $snp (@$snp){
  my $url = $self->{'link'};
  my $link = $url . $snp->{'SNP_NAME'};
  my $type = "Unknown";
  if ($snp->{'STATUS'} == 1){
    $type = "Sanger Verified";
  }
  elsif($snp->{'STATUS'} == 2){
    $type = "External Verified";
  }
  elsif($snp->{'STATUS'} == 3){
    $type = "Two-Hit";
  }
  push @features, {
		   'id'      => $snp->{'SNP_NAME'},
		   'type'    => $type,
		   'method'  => "snp",
		   'start'   => $snp->{'SNPPOS'},
		   'end'     => $snp->{'SNPPOS'},
		   'link'    => $link,
		   'linktxt' => $self->{'linktxt'},
		   'typecategory' => "snp",
		  };
}
  return @features;
}

1;
