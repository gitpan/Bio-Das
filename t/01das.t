#!/usr/bin/perl

use lib '.','./blib/lib','..';

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use constant SERVER => 'http://www.wormbase.org/db/seq/das';
use constant DSN    => 'c_elegans';
use constant LAST   => 36;

######################### We start with some black magic to print on failure.

my ($loaded,$current);

BEGIN { $| = 1; print "1..${\LAST}\n"; }
END {print "not ok 1\n" unless $loaded;}
use Bio::Das;
print "ok 1\n";
$loaded=1;

sub skip ($$) {
    my $count = shift;
    print "ok $count # skip\n";
}

sub test ($$) {
  my ($count,$flag) = @_;
  print $flag ? "ok " : "not ok ",$count,"\n";
  $current = $count;
}

sub bail {
  for ($current+1..LAST) {
    print "not ok $_\n";
  }
  exit 0;
}

my $db = Bio::Das->new(-server=>SERVER,
		       -aggregators=>['Coding_transcript{coding_exon/CDS}',
				     'alignment{EST_match/alignment}',
				    ]
		       ,
		      );
test(2,$db);
bail unless $db;  # can't continue

# test sources
my @sources = $db->sources;
test(3,@sources);
my $d = DSN;
test(4,grep /$d/,@sources);
test(5,$sources[0]->description);
test(6,$sources[0]->name);

# test types()
$db->dsn(DSN);
my @types = $db->types;
test(7,@types>1);

# test segment()
my $s = $db->segment(-ref=>'III',-start=>10_000,-stop=>15_000);
test(8,$s);
bail unless $s;

# test stylesheet
my $ss = $db->stylesheet;
test(9,$ss);
bail unless $ss;

# test segment code
my $dna = $s->dna;
test(10,$dna);
test(11,length $dna == 5001);

# test features
my @features = $s->features(-category=>'structural');
test(12,@features);

# at least one of the features should be a reference
# not working - fix
skip(13,grep {$_->reference} @features);

# at least one of the features should be "CHROMOSOME_III"
my ($i) = grep {$_ eq 'III'} @features;
test(14,$i);
bail unless $i;

# the type of this feature should be 'Segment'
# and its category should be 'structural'
test(15,lc ($i->type) eq 'region:link');
test(16,$i->category eq 'structural');

# see if we can't get some transcrips
my @t = grep {  $_->method eq 'Coding_transcript'
	      } $s->features(-category=>'transcription');
test(17,@t);

# find the first one that has subfeatures
my (@e,$t);
for (@t) {
    $t = $_;
    @e = $_->get_SeqFeatures;
    last if @e > 1;
}
$t or bail;
@e = sort {$a->start<=>$b->start} @e;
test(18,@e > 1);
test(19,$t->compound);

# are the start and end correct?
test(20,$e[0]->start == $t->start);
test(21,$e[-1]->stop == $t->stop);

# is there a link, and are they the same?
test(22,$t->link eq $e[0]->link);

# test similarity features
my @s = $s->features(-type=>'alignment:BLAT_EST_BEST'); # BLAT_EST_BEST
test(23,@s);
@s or bail;

test(24,$s[0]->can('segments'));
my @seg = $s[0]->segments or bail;
test(25,@seg);

test(26,$s[0]->source eq $seg[0]->source);
@t   = $seg[0]->target;
test(27,@t==3);
test(28,$t[0] eq $s[0]->target);

# test that stylesheets work
my ($glyph,@args) = $ss->glyph($s[0]);
test(29,$glyph);

# test parallel interface
$db = Bio::Das->new(5);
test(30,$db) or bail;

my $response = $db->features(-dsn     => SERVER.'/'.DSN,
			     -segment => ['I:1,10000',
					  'I:10000,20000'
					 ]
			     );

test(31,$response) or bail;
test(32,$response->is_success);
my $results = $response->results;
test(33,$results);
my @segments = keys %$results;
test(34,@segments == 2);
test(35,$segments[0] =~ /^I:/);
my $features = $results->{$segments[0]};
test(36,@$features>0);



