use strict; use warnings;
package TestML::Run;

use JSON::PP 'decode_json';
# use XXX;

my $operator = {
  '=='    => 'eq',
  '.'     => 'call',
  '=>'    => 'func',
  "\$''"  => 'get-string',
  '%()'   => 'pickloop',
  '*'     => 'point',
  '='     => 'set-var',
};

sub new {
  my ($class, $testml) = @_;

  return bless {
    testml => $testml,
  }, $class;
}

sub from_file {
  my ($self, $testml_file) = @_;

  $self->{testml_file} = $testml_file;

  $self->{testml} = decode_json $self->_read_file($self->{testml_file});

  return $self;
}

sub test {
  my ($self) = @_;

  $self->initialize;

  $self->test_begin;

  $self->exec($self->{code});

  $self->test_end;
}

sub initialize {
  my ($self) = @_;

  $self->{code} = $self->{testml}{code};

  unshift @{$self->{code}}, '=>', [];

  $self->{data} = [
    map {
      TestML::Block->new($_);
    } @{$self->{testml}->{data}}
  ];

  if (not $self->{bridge}) {
    my $bridge_module = $ENV{TESTML_BRIDGE};
    eval "require $bridge_module; 1" || do {
      die "Can't find Bridge module for TestML"
        if $@ =~ /^Can't locate $bridge_module/;
      die $@;
    };

    $self->{bridge} = $bridge_module->new;
  }

  return $self;
}

sub exec {
  my ($self, $expr, $context) = @_;

  $context //= [];

  return [$expr] unless ref $expr eq 'ARRAY';

  my @args = @$expr;
  my @return;
  my $call = shift @args;
  if (my $name = $operator->{$call}) {
    $call = "exec_$name";
    $call =~ s/-/_/g;
    @return = $self->$call(@args);
  }
  else {
    @args = map {
      ref eq 'ARRAY' ? $self->exec($_)->[0] : $_
    } @args;

    unshift @args, $_ for reverse @$context;

    if ($call =~ /^[a-z]/) {
      $call =~ s/-/_/g;
      die "Can't find bridge function: '$call'"
        unless $self->{bridge}->can($call);
      @return = $self->{bridge}->$call(@args);
    }
    elsif ($call =~ /^[A-Z]/) {
      $call = lc $call;
      die "Unknown TestML Standard Library function: '$call'"
        unless $self->_stdlib->can($call);
      @return = $self->_stdlib->$call(@args);
    }
    else {
      die "Can't resolve TestML function '$call'";
    }
  }

  die "Function '$call' returned more than one item"
    if @return > 1;

  return [@return];
}

sub exec_call {
  my ($self, @args) = @_;

  my $context = [];

  for my $call (@args) {
    $context = $self->exec($call, $context);
  }

  return @$context;
}

sub exec_eq {
  my ($self, $left, $right, $label) = @_;

  my $got = $self->exec($left)->[0];

  my $want = $self->exec($right)->[0];

  $label = $self->_get_label($label);

  $self->test_eq($got, $want, $label);
}

sub exec_func {
  my ($self, @args) = @_;
  my $signature = shift @args;

  for my $statement (@args) {
    $self->exec($statement);
  }

  return;
}

sub exec_get_string {
    my ($self, $string) = @_;

    $string =~ s{\{([\-\w+])\}} {
        $self->vars->{$1} || ''
    }gex;

    $string =~ s{\{\*([\-\w]+)\}} {
        $self->{block}->point->{$1} || ''
    }gex;

    $string =~ s{\{[^\}]*\}} {}g;

    return $string;
}

sub exec_pickloop {
  my ($self, $list, $expr) = @_;

  outer: for my $block (@{$self->{data}}) {
    for my $point (@$list) {
      if ($point =~ /^\*/) {
        next outer unless exists $block->{point}{substr($point, 1)};
      }
      elsif ($point =~ /^!*/) {
        next outer if exists $block->{point}{substr($point, 2)};
      }
    }
    $self->{block} = $block;
    $self->exec($expr);
  }

  delete $self->{block};
}

sub exec_point {
  my ($self, $name) = @_;

  $self->{block}{point}{$name};
}

sub exec_set_var {
  my ($self, $name, $expr) = @_;

  $self->setv($name, $self->exec($expr)->[0]);
}

#------------------------------------------------------------------------------
sub getv {
  my ($self, $name) = @_;

  return $self->{vars}{$name};
}

sub setv {
  my ($self, $name, $value) = @_;

  $self->{vars}{$name} = $value;
}

sub getp {
  my ($self, $name) = @_;

  return unless $self->{block};

  return unless $self->{block}->point->{$name};
}

#------------------------------------------------------------------------------
sub _get_label {
  my ($self, $label_expr) = @_;

  $label_expr //= '';

  my $label = $self->exec($label_expr)->[0];

  my $block_label = $self->{block}->label;

  if ($label) {
    $label =~ s/^\+/$block_label/;
    $label =~ s/\+$/$block_label/;
    $label =~ s/\{\+\}/$block_label/;
  }
  else {
    $label = $block_label;
  }

  return $label;
}

sub _stdlib {
  my ($self) = @_;

  $self->{stdlib} //= do {
    require TestML::StdLib;

    TestML::StdLib->new;
  };

  $self->{stdlib};
}

sub _read_file {
  my ($self, $file) = @_;

  open INPUT, $file
    or die "Can't open '$file' for input";

  local $/;
  my $input = <INPUT>;

  close INPUT;

  return $input;
}

#------------------------------------------------------------------------------
package TestML::Block;

sub new {
  my ($class, $data) = @_;

  return bless $data, $class;
}

sub label { return $_[0]->{label} }
sub point { return $_[0]->{point} }

1;