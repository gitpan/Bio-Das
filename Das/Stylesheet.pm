package Bio::Das::Stylesheet;

use strict;

use Carp 'croak';
use XML::Parser;
use Bio::Das::Parser;

use vars qw($VERSION @ISA);
@ISA       = qw(Bio::Das::Parser);
$VERSION = '0.04';


#
# Bio::Das::Stylesheet->new($das);
#
sub new {
  my $class = shift;
  $class = ref($class) if ref($class);

  my $source = shift;
  $source && $source->isa('Bio::Das')
    || croak "Usage: Bio::Das::Sylesheet->new(\$das)\n";

  return bless { source => $source },$class;
}

sub source { shift->{source} }

sub categories {
  my $self = shift;
  my $c = $self->_categories or return;
  keys %$c;
}

# in a scalar context, return name of glyph
# in array context, return name of glyph followed by attribute/value pairs
sub glyph {
  my $self = shift;
  my $feature = shift;
  $feature = $feature->[0] if ref($feature) eq 'ARRAY';  # hack to prevent common error
  my $category = lc $feature->category;
  my $type     = lc $feature->type;
  my $c = $self->_categories or return;
  my $d = $c->{$category} or return _format_glyph($c->{default}{default});
  my $e = $d->{$type}     or return _format_glyph($c->{$category}{default});
  _format_glyph($e);
}

# not a method
sub _format_glyph {
  my $glyph = shift;
  return unless $glyph;
  my $name = $glyph->{name};
  return $name unless wantarray;
  return ($name,%{$glyph->{attr}});
}


# parse and fill
sub _categories {
  my $self = shift;
  return $self->{category} if $self->{category};
  my $source = $self->source;
  $source->_stylesheet(-parser=>$self,-chunk=>4096);
  return $self->{category};
}

sub create_parser {
  my $self = shift;
  return XML::Parser->new( Handlers => {
					Start => sub { $self->tag_start(@_) },
					End   => sub { $self->tag_end(@_)   },
				       });
}

sub parsedone {
  my $self = shift;
  $self->SUPER::parsedone;
  delete $self->{tmp};
}

sub tag_start {
  my $self = shift;
  my ($expat,$element,%attr) = @_;

  if ($element eq 'CATEGORY') { # starting a new category section
    $self->{tmp}{cc} = $attr{id};    # cc = current category
    return;
  }

  # everything else needs a category
  my $category = $self->{tmp}{cc} or return;

  if ($element eq 'TYPE') {
    $self->{tmp}{ct} = $attr{id};   # ct = current type
    return;
  }

  # everything else needs a category and type
  my $type = $self->{tmp}{ct};

  # look for the start of a glyph
  if ($element eq 'GLYPH') {
    $self->{tmp}{glyph} = {};
    $expat->setHandlers(Char => sub { $self->do_content(@_) } );
    return;
  }

  # set the current glyph
  my $glyph = $self->{tmp}{glyph} or return;
  return if $glyph->{name};

  # we get here right after the <GLYPH> tag but before we know its name
  $glyph->{name} ||= lc $element; # e.g. "box"
  $glyph->{attr} ||= {};       # will contain list of attributes
}

sub tag_end {
  my $self = shift;
  my ($expat,$element) = @_;

  my $glyph = $self->{tmp}{glyph} or return;

  if ($element eq 'GLYPH') {
    my $category = lc $self->{tmp}{cc};
    my $type     = lc $self->{tmp}{ct};
    $self->{category}{$category}{$type} = $glyph;
    $expat->setHandlers(Char => undef);
    undef $self->{tmp}{glyph};
    return;
  }

  my $val = $self->{tmp}{value};
  defined $val or return;

  # record the value -- put dashes in front of the attributes
  $glyph->{attr}{'-'.lc $element} = $val;

  undef $self->{tmp}{value};
}

sub do_content {
  my $self = shift;
  my ($expat,$data) = @_;
  return unless $data =~ /\S/; # ignore whitespace
  chomp($data);
  $self->{tmp}{value} = $data;
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__

=head1 NAME

Bio::Das::Stylesheet - Access to DAS stylesheets

=head1 SYNOPSIS

  use Bio::Das;

  # contact the DAS server at wormbase.org
  my $das      = Bio::Das->new('http://www.wormbase.org/db/das'=>'elegans');

  # get the stylesheet
  my $style    = $das->stylesheet;

  # get features
  my @features = $das->segment(-ref=>'Locus:unc-9')->features;

  # for each feature, ask the stylesheet what glyph to use
  for my $f (@features) {
    my ($glyph_name,@attributes) = $style->glyph($f);
  }


=head1 DESCRIPTION

The Bio::Das::Stylesheet class contains information about a remote DAS
server's preferred visualization style for sequence features.  Each
server has zero or one stylesheets for each of the data sources it is
responsible for.  Stylesheets can provide stylistic guidelines for
broad feature categories (such as "transcription"), or strict
guidelines for particular feature types (such as "Prosite motif").

The glyph names and attributes are broadly compatible with the
Ace::Graphics library.

=head2 OBJECT CREATION

Bio::Das::Stylesheets are created by the Bio::Das object in response
to a call to the stylesheet() method.  The Bio::Das object must
previously have been associated with a data source.

=head2 METHODS

=over 4

=item ($glyph,@attributes) = $stylesheet->glyph($feature)

The glyph() method takes a Bio::Das::Segment::Feature object and
returns the name of a suggested glyph to use, plus zero or more
attributes to apply to the glyph.  Glyphs names are described in the
DAS specification, and include terms like "box" and "arrow".

Attributes are name/value pairs, for instance:
	   
   (-width => '10', -outlinecolor => 'black')

The initial "-" is added to the attribute names to be consistent with
the Perl name/value calling style.  The attribute list can be passed
directly to the Ace::Panel->add_track() method.

In a scalar context, glyph() will return just the name of the glyph
without the attribute list.

=item @categories = $stylesheet->categories

Return a list of all the categories known to the stylesheet.

=item $source = $stylesheet->source

Return the Bio::Das object associated with the stylesheet.

=head2 HOW GLYPH() RESOLVES FEATURES

When a feature is passed to glyph(), the method checks the feature's
type ID and category against the stylesheet.  If an exact match is
found, then the method returns the corresponding glyph name and
attributes.  Otherwise, glyph() looks for a default style for the
category and returns the glyph and attributes for that.  If no
category default is found, then glyph() returns its global default.

=head2 USING Bio::Das::Stylesheet WITH Ace::Graphics::Panel

The stylesheet class was designed to work hand-in-glove with
Ace::Graphics::Panel.  You can rely entirely on the stylesheet to
provide the glyph name and attributes, or provide your own default
attributes to fill in those missing from the stylesheet.

It is important to bear in mind that Ace::Graphics::Panel only allows
a single glyph type to occupy a horizontal track.  This means that you
must sort the different features by type, determine the suggested
glyph for each type, and then create the tracks.

The following code fragment illustrates the idiom.  After sorting the
features by type, we pass the first instance of each type to glyph()
in order to recover a glyph name and attributes applicable to the
entire track.

  use Bio::Das;
  use Ace::Graphics::Panel;

  my $das        = Bio::Das->new('http://www.wormbase.org/db/das'=>'elegans');
  my $stylesheet = $das->stylesheet;
  my $segment    = $das->segment(-ref=>'Locus:unc-9');
  @features      = $segment->features;

  my %sort;
  for my $f (@features) {
     my $type = $f->type;
     # sort features by their type, and push them onto anonymous
     # arrays in the %sort hash.
     push @{$sort{$type}},$f;   
  }
  my $panel = Ace::Graphics::Panel->new( -segment => $segment,
                                         -width   => 800 );
  for my $type (keys %sort) {
      my $features = $sort{$type};
      my ($glyph,@attributes) = $stylesheet->glyph($features->[0]);
      $panel->add_track($features=>$glyph,@attributes);
  }

To provide your own default attributes to be used in place of those
omitted by the stylesheet, just change the last line so that your
own attributes follow those provided by the stylesheet:

      $panel->add_track($features=>$glyph,
                        @attributes,
                        -connectgroups => 1,
			-key           => 1,
			-labelcolor    => 'chartreuse'
                        );

=head1 AUTHOR

Lincoln Stein <lstein@cshl.org>.

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=head1 SEE ALSO

L<Bio::Das>, L<Ace::Graphics::Panel>, L<Ace::Graphics::Track>

=cut
