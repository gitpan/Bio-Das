#!/usr/bin/perl -w

use lib '.','./blib/lib','../blib/lib';

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use constant SERVER => 'http://www.wormbase.org/db/das';
use constant DSN    => 'elegans';
use constant LAST   => 30;

######################### We start with some black magic to print on failure.

my ($loaded,$current);

BEGIN { $| = 1; print "1..${\LAST}\n"; }
END {print "not ok 1\n" unless $loaded;}
use Bio::Das;
print "ok 1\n";
$loaded=1;

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

my $db = Bio::Das->new(SERVER);
test(2,$db);

bail unless $db;  # can't continue

# test sources
my @sources = $db->sources;
test(3,@sources);
test(4,grep /elegans/,@sources);
test(5,$sources[0]->description);
test(6,$sources[0]->name);

# test types()
$db->dsn('elegans');
my @types = $db->types;
test(7,@types>1);

# test segment()
my $s = $db->segment(-ref=>'CHROMOSOME_III',-start=>5_000,-stop=>15_000);
test(8,$s);
bail unless $s;

# test stylesheet
my $ss = $db->stylesheet;
test(9,$ss);
bail unless $ss;

# test segment code
my $dna = $s->dna;
test(10,$dna);
test(11,length $dna == 10001);

# test features
my @features = $s->features(-category=>'structural');
test(12,@features);

# at least one of the features should be a reference
test(13,grep {$_->reference} @features);

# at least one of the features should be "CHROMOSOME_III"
my ($i) = grep {$_ eq 'III'} @features;
test(14,$i);
bail unless $i;

# the type of this feature should be 'Link'
# and its category should be 'structural'
test(15,$i->type eq 'Link');
test(16,$i->category eq 'structural');

# see if we can't get some transcrips
my @t = grep {  $_->type eq 'transcript' &&
                $_->method eq 'composite'
	      } $s->features(-category=>'transcription');
test(17,@t);

# see if the first one has some exons
my $t = $t[0] or bail;
my @e = $t->exons or bail;
test(18,@e > 1);

my @i = $t->introns;
test(19,@e - @i == 1);  # exons - introns - 1

# test the special "Transcript" fetch
@t = $s->features('transcript');
my @c = grep {   $_->type eq 'transcript' &&
		   $_->method eq 'composite'
		 } @t;
test(20,@t==@c);

# are the start and end correct?
test(21,$e[0]->start == $t->start);
test(22,$e[-1]->stop == $t->stop);

# is there a link, and are they the same?
test(23,$t->link eq $e[0]->link);

# test similarity features
my @s = $s->features(-type=>'EST');
test(24,@s);
@s or bail;

test(25,$s[0]->can('segments'));
my @seg = $s[0]->merged_segments or bail;
test(26,@seg);
test(27,$s[0]->type eq $seg[0]->type);
@t   = $seg[0]->target;
test(28,@t==3);
test(29,$t[0] eq $s[0]->target);

# test that stylesheets work
my ($glyph,@args) = $ss->glyph($s[0]);
test(30,$glyph);
