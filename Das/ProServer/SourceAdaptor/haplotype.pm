#########
# Author: jc3
# Maintainer: jc3
# Created: 2003-09-17
# Last Modified: 2003-09-17
# Provides DAS features for Haplotype Information.

package Bio::Das::ProServer::SourceAdaptor::haplotype;

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
  my $root = "/ensweb/www/server";
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
  $self->{'link'} = "http://intweb.sanger.ac.uk/cgi-bin/humace/snp_report.pl?block=";
  $self->{'linktxt'} = "more information";
}

sub length{
  my ($self,$seg) = @_;
  if (!$self->{'_length'}->{$seg} && $seg =~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
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
		       <CATEGORY id="haplotype">
		        <TYPE id="Hap African American">
		         <GLYPH>
		          <BOX>
		           <FGCOLOR>blue4</FGCOLOR>
                           <FONT>sanserif</FONT>
		           <BGCOLOR>black</BGCOLOR>
		          </BOX>
		         </GLYPH>
		        </TYPE>
		        <TYPE id="Hap Cauc Unrelateds">
		         <GLYPH>
		          <BOX>
		           <FGCOLOR>blueviolet</FGCOLOR>
                           <FONT>sanserif</FONT>
		           <BGCOLOR>black</BGCOLOR>
		          </BOX>
		         </GLYPH>
		        </TYPE>
		        <TYPE id="Hap Asians">
		         <GLYPH>
		          <BOX>
		           <FGCOLOR>darkslateblue</FGCOLOR>
                           <FONT>sanserif</FONT>
		           <BGCOLOR>black</BGCOLOR>
		          </BOX>
		         </GLYPH>
		        </TYPE>
		        <TYPE id="Hap CEPH family">
		         <GLYPH>
		          <BOX>
		           <FGCOLOR>lightblue3</FGCOLOR>
                           <FONT>sanserif</FONT>
		           <BGCOLOR>black</BGCOLOR>
		          </BOX>
		         </GLYPH>
		        </TYPE>
		        <TYPE id="default">
		         <GLYPH>
		          <BOX>
		           <FGCOLOR>red</FGCOLOR>
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
  if (!$end || $segid !~ /^(10|20|(1?[1-9])|(2?[12])|[XY])$/i){
    return @features;
  }

 my  $query = qq(SELECT 	distinct (mapped_snp.position + seq_seq_map.START_COORDINATE -1) as snppos,
	mapped_snp.id_snp as snp_id,
	sb.id_block as block,
	b.name as block_name,
	b.id_block_set as block_set,
	p.description as population,
	snp_name.snp_name as snp_name,
	bs.maf as maf
FROM 	chrom_seq,
	seq_seq_map,
	snp_sequence,
	mapped_snp,
	snp_name,
	snp,
	snp_block sb,
	block b,
	block_set bs,
	population p,
	database_dict
WHERE	chrom_seq.DATABASE_SEQNAME='$segid'
AND 	chrom_seq.ID_CHROMSEQ = seq_seq_map.ID_CHROMSEQ
AND 	snp_sequence.ID_SEQUENCE = seq_seq_map.SUB_SEQUENCE
AND 	mapped_snp.ID_SEQUENCE = snp_sequence.ID_SEQUENCE
AND 	snp_name.id_snp = mapped_snp.id_snp
AND 	snp.id_snp = snp_name.id_snp
AND	snp.id_snp = sb.id_snp
AND	sb.id_block = b.id_block
AND	b.id_block_set = bs.id_block_set
AND	bs.id_pop = p.id_pop	
AND 	snp_name.snp_name_type = 1
AND 	chrom_seq.DATABASE_SOURCE = database_dict.ID_DICT
AND 	database_dict.DATABASE_NAME = 'NCBI'
AND 	database_dict.DATABASE_VERSION = '33'
AND 	(mapped_snp.position + seq_seq_map.START_COORDINATE -1) BETWEEN '$start' AND '$end'
ORDER BY snppos);

my $haplotype = $self->transport->query($query);

  for my $haplotype (@$haplotype){
    my $url = $self->{'link'};
    my $link = $url . $haplotype->{'BLOCK'};

    push @features, {
		     'type'    => $haplotype->{'POPULATION'},
		     'id'      => $haplotype->{'BLOCK'},
		     #'group'   => $haplotype->{'BLOCK_SET'},
		     'method'  => "haplotype",
		     'start'   => $haplotype->{'SNPPOS'},
		     'end'     => $haplotype->{'SNPPOS'},
		     'link'    => $link,
		     'linktxt' => $self->{'linktxt'},
		     'typecategory' => "haplotype",
		     'note'    => qq(MAF: $haplotype->{'MAF'}),
		    };
  }
  return @features;
}
1;
