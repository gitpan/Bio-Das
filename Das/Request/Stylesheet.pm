package Bio::Das::Request::Stylesheet;
# $Id: Stylesheet.pm,v 1.2 2003/05/22 19:46:55 avc Exp $
# this module issues and parses the stylesheet command, with arguments -dsn

use strict;
use Bio::Das::Request;
use Bio::Das::Stylesheet;
use Bio::Das::Util 'rearrange';

use vars '@ISA';
@ISA = 'Bio::Das::Request';

# callback invoked every time a <type> section is ready
# it will be called with the following arguments:
# $category,$type,$zoom,$glyph,$attributes
# All arguments are strings with exception of $attributes, which is a
# hashref of attribute=>value pairs
sub new {
  my $pack = shift;
  my ($dsn,$callback) = rearrange([['dsn','dsns'],'callback'],@_);
  my $self = $pack->SUPER::new(-dsn => $dsn,
			       -callback  => $callback,
			       -args => { } );
  $self;
}

sub command { 'stylesheet' }

sub t_DASSTYLE {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {
    $self->clear_results;
  }
  delete $self->{tmp};
}

sub t_STYLESHEET {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {
    my $stylesheet = Bio::Das::Stylesheet->new;
    $self->{tmp}{stylesheet} = $stylesheet;
  } elsif (!$self->callback) {
    $self->add_object($self->{tmp}{stylesheet});
  }
}

sub t_CATEGORY {
  my $self = shift;
  my $attrs = shift;
  if ($attrs) {    # segment section is starting
    $self->{tmp}{category} = $attrs->{id};
  }
  else {  # reached the end of the category
    delete $self->{tmp}{category};
  }
}

sub t_TYPE {
  my $self = shift;
  my $attrs = shift;

  if ($attrs) {  # start of tag
    $self->{tmp}{type} = $attrs->{id};
  } else {
    my $t = $self->{tmp};
    delete @{$t}{qw(type zoom glyph attributes)};
  }
}

sub t_GLYPH {
  my $self = shift;
  my $attrs = shift;
  my $t = $self->{tmp};

  if ($attrs) {  # start of tag
    $t->{zoom}  = $attrs->{zoom};
    $t->{glyph} = 'pending';
  } else {
    my %attributes = $t->{attributes} ? %{$t->{attributes}} : (); # copy
    $t->{stylesheet}->add_type(@{$t}{qw(category type zoom glyph)},\%attributes);
    if (my $cb = $self->callback) {
      eval {$cb->(@{$t}{qw(category type zoom glyph)},\%attributes)};
      warn $@ if $@;
    }
  }
}

# handle other tags
sub do_tag {
  my $self = shift;
  my ($tag,$attrs) = @_;
  if (exists $self->{tmp}{glyph}) { # in a glyph section
    if ($self->{tmp}{glyph} eq 'pending') { # must be a glyph name tag
      $self->{tmp}{glyph} = lc $tag;
    }
    elsif (!$attrs && lc $tag ne $self->{tmp}{glyph}) {  # attribute
      $self->{tmp}{attributes}{lc $tag} = $self->char_data;
    }
  }
}

1;
