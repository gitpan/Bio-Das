package Bio::Das::Segment;

use strict;

use Carp 'croak';
use XML::Parser;
use Bio::Das::Segment::Feature;
use Bio::Das::Segment::GappedAlignment;
use Bio::Das::Segment::Transcript;
use Bio::Das::Util;  # for rearrange()
use Bio::Das::Parser;
use Bio::Das::Type;

use overload '""' => 'toString';

use vars qw($VERSION @ISA);
@ISA       = qw(Bio::Das::Parser);

# we follow the RangeI interface, but don't actually need to load this
#@ISA       = qw(Bio::Das::Parser Bio::RangeI);

$VERSION = '0.05';
*primary_tag = \&type;

#
# Das::Segment->new($das,$refseq,$start,$stop);
#
sub new {
  my $class = shift;
  $class = ref($class) if ref($class);

  my ($source,$refseq,$start,$stop) = @_;
  $source && $source->isa('Bio::Das') 
    || croak 'Usage: Bio::Das::Segment->new($das,$refseq,$start,$stop)';

  return bless {
		refseq  => $refseq,
		source  => $source,
		start   => $start,
		stop     => $stop,
	       },$class;
}

# return subsequence
sub segment {
  my $self = shift;
  my ($start,$stop) = @_;
  return ref($self)->new($self->source,$self->refseq,$start,$stop);
}

# return list of the feature types available
sub types {
  my $self = shift;
  my $hash = $self->_types;
  return map {$hash->{$_}{type}} keys %$hash unless @_;
  my $type = shift;
  return $hash->{$type}{count};
}

sub type {
  my $self = shift;
  return 'Sequence';  # generic
}

# return list of toplevel objects beneath the current one
sub entry_points {
  my $self    = shift;
  my $source = ref($self) ? $self->source : shift;
  my $refseq   = shift;

  if (ref($refseq) && $refseq->can('refseq')) {
    $refseq = $refseq->refseq;
  } elsif (ref $self) {
    $refseq = $self->refseq;
  }

  my @args = $refseq ? (-ref => $refseq) : ();

  # clear out instane variables
  $self = bless {source => $source},$self unless ref $self;
  $self->{entry_points} = [];
  $source->_entry_points(-parser=>$self,-chunk=>4096,@args);
  return @{$self->{entry_points}};
}

sub toString {
  my $self = shift;
  my $label = $self->refseq or return overload::StrVal($self);
  $label .= "/" . join ',',($self->start,$self->stop)
    if defined $self->{start} && defined $self->{stop};
  return $label;
}

sub source {
  my $self = shift;
  my $d = $self->{source};
  $self->{source} = shift if @_;
  $d;
}

sub refseq {
  my $self = shift;
  my $d = $self->{refseq};
  $self->{refseq} = shift if @_;
  $d;
}

sub start {
  my $self = shift;
  my $d = $self->{start};
  $self->{start} = shift if @_;
  $d;
}

sub end {
  my $self = shift;
  croak "end(): read-only method" if @_;
  $self->{stop};
}

# so that we can pass a whole segment to Bio::Graphics
sub type { 'Segment' }

sub stop {
  my $self = shift;
  my $d = $self->{stop};
  $self->{stop} = shift if @_;
  $d;
}

sub length {
  my $self = shift;
  croak "length(): read-only method" if @_;
  $self->stop - $self->start + 1;
}

# no strand on segments
sub strand { 0; }

sub offset {
  my $self = shift;
  croak "offset(): read-only method" if @_;
  $self->stop - 1;
}

sub dna {
  my $self = shift;
  return $self->{dna} if defined $self->{dna};

  my $source = $self->source;
  my $ref = $self->refseq;
  if (defined $self->start && defined $self->stop) {
    $ref .= ":".$self->start.",".$self->stop;
  }
  my @args = (-segment => $ref);
  $source->_dna(-parser=>$self,-chunk=>4096,@args);
  return $self->{dna};
}

sub create_parser {
  my $self = shift;
  return XML::Parser->new( Handlers => {
					Start => sub { $self->guess_doctype(@_) },
				       });
}

sub parsedone {
  my $self = shift;
  $self->SUPER::parsedone;
  delete $self->{homologies};
  delete $self->{transcripts};
  delete $self->{tmp};
}

sub guess_doctype {
  my $self = shift;
  my ($expat,$element) = @_;

  if ($element eq 'DASDNA') {
    $expat->setHandlers(Start => sub { $self->do_dna('start',@_) },
			End   => sub { $self->do_dna('end',@_)  },
			Char  => sub { $self->do_dna('contents',@_) }
			);
    return;
  }

  if ($element eq 'DASGFF') {
    $expat->setHandlers(
			Start => sub { $self->do_feature_start(@_) },
			End   => sub { $self->do_feature_end(@_)  },
		       );
    return;
  }

  if ($element eq 'DASEP') {
    $expat->setHandlers(
			Start => sub { $self->do_entry_point(@_) },
		       );
    return;
  }

  if ($element eq 'DASTYPES') {
    $expat->setHandlers(
			Start => sub { $self->do_types('start',@_) }
		       );
    return;
  }
}

sub features {
  my $self = shift;
  my ($types,$categories,@filter);
  if ($_[0] =~ /^-/) {
    ($types,$categories) = rearrange([['type','types'],['category','categories']],@_);
    push @filter,type=>$types          if $types;      # a regular expression, DAS style
    push @filter,category=>$categories if $categories; # a regular expression, DAS style
  } else {
    # a list of type:subtype, Ace::Sequence style
    my @f = map { $_ eq 'transcript' ? qw(intron exon transcript CDS) : $_ } 
            grep {$_ ne ''} @_;
    push @filter,type=>\@f;
  }

  my $source = $self->source;

  undef $self->{features};
#  my @args = (-ref  => $self->refseq);
#  push @args,-start => $self->start if defined $self->start;
#  push @args,-stop  => $self->stop if defined $self->stop;

  my $ref = $self->refseq;
  if (defined $self->start && defined $self->stop) {
    $ref .= ":".$self->start.",".$self->stop;
  }
  my @args = (-segment => $ref);
  push @args,@filter if @filter;
  my $result = $source->_features(-parser=>$self,-chunk=>4096,@args);
  unless ($result) {
    $self->error($source->error);
    return;
  }
  return @{$self->{features}} if $self->{features};
}

sub error {
  my $self = shift;
  if (@_) {
    $self->{error} = join '',@_;
    return;
  } else {
    return $self->{error};
  }
}

sub do_dna {
  my $self = shift;
  my $action = shift;

  if ($action eq 'start') {  # start of a tag
    my ($expat,$element,%attr) = @_;
    if ($element eq 'SEQUENCE') {
      $self->{refseq}  = $attr{id}    if defined $attr{id};
      $self->{start}   = $attr{start} if defined $attr{start};
      $self->{stop}    = $attr{stop}  if defined $attr{stop};
    } elsif ($element eq 'DNA') {
      $self->{dna} = '';
    }
    return;
  }

  if ($action eq 'contents') {
    return unless defined $self->{dna};
    my ($expat,$data) = @_;
    chomp($data);  # remove newlines, if any
    return unless $data;
    $self->{dna} .= $data;
    return;
  }

  if ($action eq 'end') {
    # nothing to do here...
  }
}

sub do_feature_start {
  my $self = shift;

  my ($expat,$element,%attr) = @_;
  if ($element eq 'SEGMENT') {
    $self->{refseq}  = $attr{id}    if defined $attr{id};
    $self->{start}   = $attr{start} if defined $attr{start};
    $self->{stop}    = $attr{stop}  if defined $attr{stop};
    $self->{features} = [];
    return;
  }

  if ($element eq 'FEATURE') { # start a new feature "cf" == "current feature"
    $self->{cf} = Bio::Das::Segment::Feature->new(
						  -segment => $self,
						  -id      => $attr{id},
						  -label   => $attr{label},
						 );
    return;
  }

  return unless my $cf = $self->{cf};  # don't process anything unless a feature is open

  if ($element eq 'TYPE') {
    my $cft = $self->{cft} ||= Bio::Das::Type->new;
    $cft->id($attr{id});
    $cft->category($attr{category});
    $cft->reference(1) if defined $attr{reference} && $attr{reference} eq 'yes';
    $self->{fd} = '';  # fd = "feature data"
    $expat->setHandlers(Char => sub { $self->do_feature_contents(@_) } );
    return;
  }

  if ($element eq 'METHOD') {
    my $cft = $self->{cft} ||= Bio::Das::Type->new;
    $cft->method($attr{id});
    $self->{fd} = '';  # fd = "feature data"
    $expat->setHandlers(Char => sub { $self->do_feature_contents(@_) } );
    return;
  }

  if ($element =~ /^(START|END|SCORE|ORIENTATION|PHASE|NOTE)$/) {
    $self->{fd} = '';  # fd = "feature data"
    $expat->setHandlers(Char => sub { $self->do_feature_contents(@_) } );
    return;
  }

  if ($element eq 'GROUP') {
    $cf->group($attr{id});
    return;
  }

  if ($element eq 'LINK') {
    $cf->link($attr{href});
    $self->{fd} = '';  # fd = "feature data"
    $expat->setHandlers(Char => sub { $self->do_feature_contents(@_) } );
    return;
  }
  if ($element eq 'TARGET') {
    $cf->target(@attr{qw(id start stop)});
    $self->{fd} = '';  # fd = "feature data"
    $expat->setHandlers(Char => sub { $self->do_feature_contents(@_) } );
    return;
  }
}

sub do_feature_end {
  my $self = shift;
  my ($expat,$element) = @_;
  my $cf =  $self->{cf} or return;
  if (defined $self->{fd}) {
    # strip whitespace
    $self->{fd} =~ s/\A\s+//;
    $self->{fd} =~ s/\s+\Z//;
  }

  if ($element eq 'FEATURE') {

    if ($cf->category =~ /^(homology|similarity)$/) {  # a similarity - merge groups into gapped alignments
      $self->add_alignment($cf);
    }

    elsif ($cf->type =~ /^(CDS|exon|intron|transcript)$/) {  # transcript - merge into a single transcript object
      my $subtype = $1;
      $self->add_transcript($cf,$subtype);
    }

    else {
      push @{$self->{features}},$cf;
    }

    undef $self->{cf};
  }

  elsif ($element eq 'TYPE' && (my $cft = $self->{cft})) {
    $cft->label($self->{fd});
    $cft->id($cft->label) unless $cft->id;
    if ($cft->complete) {
      $cf->type($self->_cache_type($cft));
      undef $self->{cft};
    }
  }

  elsif ($element eq 'METHOD' && ($cft = $self->{cft})) {
    $cft->method_label($self->{fd});
    $cft->method($cft->method_label) unless $cft->method;
    if ($cft->complete) {
      $cf->type($self->_cache_type($cft));
      undef $self->{cft};
    }
  }

  elsif ($element =~ /^(START|END|SCORE|ORIENTATION|PHASE|NOTE)$/) {
    my $attribute = lc $element;
    $cf->$attribute($self->{fd});
  }

  elsif ($element eq 'LINK') {
    $cf->link_label($self->{fd});
  }

  elsif ($element eq 'TARGET') {
    $cf->target_label($self->{gd});
  }

  undef $self->{fd};
  $expat->setHandlers(Char => undef);
}

sub do_feature_contents {
  my $self = shift;
  return unless defined $self->{fd};
  my ($expat,$data) = @_;

  chomp($data);  # remove newlines, if any
  return unless $data;
  $self->{fd} .= $data;
  return;
}

sub file_url {
  my $self = shift;
  my $scalar = shift;
  if ($$scalar !~ m!^/!) {
    require Cwd;
    my $cwd = Cwd::cwd();
    $$scalar = "$cwd/$$scalar";
  }
  $$scalar = "file:$$scalar";
}

sub add_alignment {
  my $self = shift;
  my $cf = shift;  # current feature
  my $group = $cf->group;
  unless ($self->{homologies}{$group}) {
    my $alignment = Bio::Das::Segment::GappedAlignment->new($cf); # rebless
    $self->{homologies}{$group} = $alignment;
    push @{$self->{features}},$alignment;
  }
  $self->{homologies}{$group}->add_segment($cf);
}

sub add_transcript {
  my $self = shift;
  my ($cf,$subpart) = @_;

  my $group = $cf->group;
  unless ($self->{transcripts}{$group}) {
    my $transcript = Bio::Das::Segment::Transcript->new($cf); # rebless
    $self->{transcripts}{$group} = $transcript;
    push @{$self->{features}},$transcript;
  }

  # indirect method calls would be more elegant, but not supported
  # before perl 5.6.  Otherwise, we'd do $self->{transcripts}{$group}->add_$subpart($cf);
  if ($subpart eq 'CDS') {
    $self->{transcripts}{$group}->add_cds($cf);
  } elsif ($subpart eq 'intron') {
    $self->{transcripts}{$group}->add_intron($cf);
  } elsif ($subpart eq 'exon') {
    $self->{transcripts}{$group}->add_exon($cf);
  }
}


# A little bit more complex - assemble a list of "transcripts"
# consisting of Das::Segment::Transcript objects.  These objects
# contain a list of exons and introns as well as inherited methods
sub transcripts {
  my $self    = shift;
  my $curated = shift;
  my $ef       = $curated ? "exon:curated"   : "exon";
  my $if       = $curated ? "intron:curated" : "intron";
  my $cds      = $curated ? "cds:curated" : "cds";
  my @features = $self->features($ef,$if,$cds);
  return grep {$_->type eq 'transcript'} @features;
}

# merge multiple types into singles
sub _cache_type {
  my $self = shift;
  my $feature_type = shift;
  my $key = $feature_type->_key;
  return $self->{cached_types}{$key} ||= $feature_type;
}

# parse list of entry points
sub do_entry_point {
  my $self = shift;
  my ($expat,$element,%attr) = @_;
  return unless $element eq 'SEGMENT';
  my $segment = ref($self)->new($self->source,$attr{id},$attr{start},$attr{stop});
  push @{$self->{entry_points}},$segment;
}

# get list of types
sub _types {
  my $self = shift;
  return $self->{types} if exists $self->{types};

  my $source = $self->source;
#  my @args = (-ref  => $self->refseq);
#  push @args,-start => $self->start if defined $self->start;
#  push @args,-stop  => $self->stop if defined $self->stop;


  my $ref = $self->refseq;
  if (defined $self->start && defined $self->stop) {
    $ref .= ":".$self->start.",".$self->stop;
  }
  my @args = (-segment => $ref);

  $source->_types(-parser=>$self,-chunk=>4096,@args);
  $self->{types};
}

# parse list of types
sub do_types {
  my $self = shift;
  my $action = shift;

  if ($action eq 'start') {
    my ($expat,$element,%attr) = @_;
    return unless $element eq 'TYPE';
    $self->{tmp}{attr} = \%attr;
    $self->{tmp}{val} = '';
    $expat->setHandlers(
			End  => sub { $self->do_types('end',@_) },
			Char => sub { $self->do_types('char',@_) }
		       );
    return;
  }

  if ($action eq 'end') {
    my ($expat,$element) = @_;
    my $attr = $self->{tmp}{attr} or return;
    my $val  = $self->{tmp}{val};
    my $type = Bio::Das::Type->new($attr->{id},
				   $attr->{method},
				   $attr->{category});
    $self->{types}{$type}{type}  = $type;
    $self->{types}{$type}{count} = $val;
    $expat->setHandlers( End  => undef,
			 Char => undef,
		      );
    return;
  }

  if ($action eq 'char') {
    my ($expat,$data) = @_;
    chomp $data;
    next unless $data =~ /(\d+)/;
    $self->{tmp}{val} .= $1;
    return;
  }
}


##################### Bio::RangeI compatibility ####################

# geometric functions for Bio::RangeI interface
sub overlaps {
  my $self = shift;
  my $otherRange = shift;
  if ($otherRange->can('refseq')) {
    return unless $self->refseq eq $otherRange->refseq;
  }
  $self->contains_pt($otherRange->start) ||
    $self->contains_pt($otherRange->end);
}

sub contains {
  my $self = shift;
  my $otherRange = shift;
  if ($otherRange->can('refseq')) {
    return unless $self->refseq eq $otherRange->refseq;
  }
  $self->contains_pt($otherRange->start) &&
    $self->contains_pt($otherRange->end);
}

sub equals {
  my $self = shift;
  my $otherRange = shift;
  if ($otherRange->can('refseq')) {
    return unless $self->refseq eq $otherRange->refseq;
  }
  return $self->start eq $otherRange->start &&
    $self->end eq $otherRange->end;
}

sub intersection {
  my $self = shift;
  my $otherRange = shift;
  return unless $self->overlaps($otherRange);
  my $start = $self->start <= $otherRange->start ? $otherRange->start
                                                 : $self->start;
  my $end   = $self->end   <= $otherRange->end   ? $self->end
                                                 : $otherRange->end;
  return ($start,$end,0);
}

sub union {
  my $self = shift;
  my ($min,$max);
  foreach ($self,@_) {
    $min  = $_->start if !defined($min) || $min > $_->start;
    $max  = $_->end   if !defined($max) || $max < $_->end;
  }
  return ($min,$max,0);
}

sub contains_pt {
  my $self = shift;
  my $pt = shift;
  return $self->start <= $pt && $self->end >= $pt;
}

1;
__END__

=head1 NAME

Bio::Das::Segment - Genomic segments from Distributed Annotation System

=head1 SYNOPSIS

  use Bio::Das;

  # contact a DAS server using the "elegans" data source
  my $das      = Bio::Das->new('http://www.wormbase.org/db/das' => 'elegans');

  # fetch a segment
  my $segment  = $das->segment(-ref=>'CHROMOSOME_I',-start=>10_000,-stop=>20_000);

  # get features and DNA from segment
  my @features = $segment->features;
  my $dna      = $segment->dna;
  my @entry_points = $segment->entry_points;
  my @types        = $segment->types;

=head1 DESCRIPTION

Bio::Das provides access to genome sequencing and annotation databases
that export their data in Distributed Annotation System (DAS) format.
This system is described at http://biodas.org.

The Bio::Das::Segment class is used to retrieve information about a
genomic segment from a DAS server. You may retrieve a list of
(optionally filtered) annotations on the segment, a summary of the
feature types available across the segment, or the segment's DNA
sequence.

=head2 OBJECT CREATION

Bio::Das::Segment objects are usually created by calling the segment()
method of a Bio::Das object created earlier.  See L<Bio::Das> for
details.  Under some circumstances, you might wish to create an object
directly using Bio::Das::Segment->new():

=over 4

=item $segment = Bio::Das::Segment->new($source,$refseq,$start,$stop)

Create a segment using the indicated reference sequence ID, between
the indicated start and stop positions.  B<$source> contains a
reference to the Bio::Das object to be used to access the data.  The
B<$start> and B<$stop> arguments are optional, and if not provided
will assume the defaults described in L<Bio::Das>.

=back

=head2  OBJECT METHODS

Once created, a number of methods allow you to query the segment for
its features and/or DNA.

=over 4

=item @features = $segment->features(@filter)

=item @features = $segment->features(-type=>$type,-category=>$category)

The features() method returns annotations across the length of the
segment.  Two forms of this method are recognized.  In the first form,
the B<@filter> argument contains a series of category names to
retrieve.  Each category may be further qualified by a regular
expression which will be used to filter features by their type ID.
Filters have the format "category:typeID", where the category and type
are separated by a colon.  The typeID and category names are treated
as an unanchored regular expression (but see the note below).  As a
special cse, you may use a type of "transcript" to fetch composite
transcript model objects (the union of exons, introns and cds
features).

Example 1: retrieve all the features in the "similarity" and
"experimental" categories:

  @features = $segment->features('similarity','experimental');

Example 2: retrieve all the similarity features of type EST_elegans
and EST_GENOME:

  @features = $segment->features('similarity:^EST_elegans$','similarity:^EST_GENOME$');

Example 3: retrieve all similarity features that have anything to do
with ESTs:

  @features = $segment->features('similarity:EST');

Example 4: retrieve all the transcripts and experimental data

  @genes = $segment->features('transcript','experimental')

In the second form, the type and categories are given as named
arguments.  You may use regular expressions for either typeID or
category.  It is also possible to pass an array reference for either
argument, in which case the DAS server will return the union of the
features.

Example 5: retrieve all the features in the "similarity" and
"experimental" categories:

  @features = $segment->features(-category=>['similarity','experimental']);

Example 6: retrieve all the similarity features of type EST_elegans
and EST_GENOME:

  @features = $segment->features(-category=>'similarity',
                                 -type    =>/^EST_(elegans|GENOME)$/
                                 );

Example 7: retrieve all features that have anything to do
with ESTs:

  @features = $segment->features(-type=>/EST/);

The return value from features() is a list of
Bio::Das::Segment::Feature objects.  See L<Bio::Das::Segment::Feature>
for details.  Also see the section below on automatic feature merging.

NOTE: Currently (March 2001) the WormBase DAS server does not allow
you to use regular expressions in categories.

=item $dna = $segment->dna

Return the DNA corresponding to the segment.  The return value is a
simple string, and not a Bio::Sequence object.  This method may return
undef when used with a DAS annotation server that does not maintain a
copy of the DNA.

=item @types = $segment->types

=item $count = $segment->types($type)

This methods summarizes the feature types available across this
segment.  The items in this list can be used as arguments to
features().

Called with no arguments, this method returns an array of
Das::Segment::Type objects.  See the manual page for details.  Called
with a TypeID, the method will return the number of instances of the
named type on the segment, or undef if the type is invalid.  Because
the list and count of types is cached, there is no penalty for
invoking this method several times.

=item @entry_points = $segment->entry_points

The entry_points() method returns a list of landmarks across the
segment.  These landmarks can in turn be used as reference sequences
for further calls into the genome.

The return value is an array of Bio::Das::Segment objects, or an empty
listif this segment contains no entry points.

NOTE: This is not the recommended way to fetch the assembly.  It is
better to filter the segment for annotations in the "structural"
category that are marked by the server as belonging to the assembly
(the particular typeID to use is server-dependent).

=back

=head2 ACCESSORS

The following accessors can be used to examine and change
Bio::Das::Segment settings.  Called with no arguments, the accessors
return the current value of the setting.  Called with a single
argument, the accessors change the setting and return its previous
value.

  Accessor         Description
  --------         -----------
  refseq()         Get/set the reference sequence
  start()          Get/set the start of the segment relative to the
		     reference sequence
  stop()           Get/set the end of the segment relative to the
		     reference sequence

=head2 AUTOMATIC FEATURE MERGING

Bio::Das::Segment detects and merges two common type of annotation:
gene models and gapped alignments.

=over 4

=item Gene Models

Features of type "intron", "exon" and "CDS" that share the same DAS
group ID are combined into Bio::Das::Segment::Transcript objects.
These are similar to Bio::Das::Segment::Feature, except for having
methods for retrieving their component introns, exons and CDSs.
Merged transcript objects have type "transcript" and category
"transcription".  See L<Bio::Das::Segment::Transcript> for more
information.

=item Gapped Alignments

Features of category "similarity" or "homology" are combined together
into single Bio::Das::Segment::GappedAlignment objects if they share
the same group ID.  These objects are similar to
Bio::Das::Segment::Feature except that they have methods for
retrieving the individual aligned segments.  Gapped alignment objects
have the type and category of the first alignmented component.  See
See L<Bio::Das::Segment::GappedAlignment> for more information.

=back

Bio::Das::Segment provides a convenience method for retrieving
transcripts:

=over 4

=item @transcripts = $segment->transcripts([$curated])

Retrieves all transcript models by fetching features of type 'exon',
'intron', and 'cds'.  If $curated is a true value, then only curated
transcripts are returned.  Otherwise the list includes both curated
and uncurated transcripts (which may contain both curated and
uncurated parts).  This may not work with every DAS server, as it
relies on hard-coded type IDs.

=back

=head2 Bio::RangeI METHODS

In addition to the methods listed above, Bio::Das::Segment implements
all the methods required for the Bio::RangeI class.

=head2 STRING OVERLOADING

The Bio::Das::Segment class is overloaded to produce a human-readable
string when used in a string context.  The string format is:

   referenceID/start,end

The start and end positions may be omitted if they are unspecified.
The overloaded stringify method is toString().

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 SEE ALSO

L<Bio::Das>, L<Bio::Das::Type>, L<Bio::Das::Segment::Feature>,
L<Bio::Das::Transcript>, L<Bio::Das::Segment::GappedAlignment>,
L<Bio::RangeI>

=cut
