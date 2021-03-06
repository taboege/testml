use strict; use warnings;
package TestMLFunction;

sub new {
  my ($class, $func) = @_;
  return bless {func => $func}, $class;
}

package TestML::Run;

use JSON::PP;

use utf8;
use boolean;
use Scalar::Util;

# use XXX;

my $vtable = {
  '=='    => [
    'assert_eq',
    'assert_%1_eq_%2', {
      'str,str' => '',
      'num,num' => '',
      'bool,bool' => '',
    },
  ],
  '~~'    => [
    'assert_has',
    'assert_%1_has_%2', {
      'str,str' => '',
      'str,list' => '',
      'list,str' => '',
      'list,list' => '',
    },
  ],
  '=~'    => [
    'assert_like',
    'assert_%1_like_%2', {
      'str,regex' => '',
      'str,list' => '',
      'list,regex' => '',
      'list,list' => '',
    },
  ],

  '.'     => 'exec_dot',
  '%'     => 'each_exec',
  '%<>'   => 'each_pick',
  '<>'    => 'pick_exec',
  '&'     => 'call_func',

  q{$''}  => 'get_str',
  ':'     => 'get_hash',
  '[]'    => 'get_list',
  '*'     => 'get_point',

  '='     => 'set_var',
  '||='   => 'or_set_var',
};

my $types = {
  '=>' => 'func',
  '/' => 'regex',
  '!' => 'error',
  '?' => 'native',
};

#------------------------------------------------------------------------------
sub new {
  my ($class, %params) = @_;

  my $testml = $params{testml};

  return bless {
    file => $params{file},
    version => $testml->{testml},
    code => $testml->{code},
    data => $testml->{data},

    bridge => $params{bridge},
    stdlib => $params{stdlib},

    vars => {},
    block => undef,
    warned_only => false,
    error => undef,
    thrown => undef,
  }, $class;
}

sub from_file {
  my ($self, $file) = @_;

  $self->{file} = $file;

  open INPUT, $file
    or die "Can't open '$file' for input";

  my $testml = decode_json do { local $/; <INPUT> };

  $self->{version} = $testml->{version};
  $self->{code} = $testml->{code};
  $self->{data} = $testml->{data};

  return $self;
}

sub test {
  my ($self) = @_;

  $self->testml_begin;

  for my $statement (@{$self->{code}}) {
    $self->exec_expr($statement);
  }

  $self->testml_end;

  return;
}

#------------------------------------------------------------------------------
sub exec {
  my ($self, $expr) = @_;

  $self->exec_expr($expr)->[0];
}

sub exec_expr {
  my ($self, $expr, $context) = @_;

  $context //= [];

  return [$expr] unless $self->type($expr) eq 'expr';

  my @args = @$expr;
  my @return;
  my $name = shift @args;
  my $opcode = $name;
  if (my $call = $vtable->{$opcode}) {
    $call = $call->[0] if ref($call) eq 'ARRAY';
    @return = $self->$call(@args);
  }
  else {
    unshift @args, $_ for reverse @$context;

    if (defined(my $value = $self->{vars}{$name})) {
        if (@args) {
          die "Variable '$name' has args but is not a function"
            unless $self->type($value) eq 'func';
          @return = $self->exec_func($value, \@args);
        }
        else {
          @return = ($value);
        }
    }
    elsif ($name =~ /^[a-z]/) {
      @return = $self->call_bridge($name, @args);
    }
    elsif ($name =~ /^[A-Z]/) {
      @return = $self->call_stdlib($name, @args);
    }
    else {
      die "Can't resolve TestML function '$name'";
    }
  }

  return [@return];
}

sub exec_func {
  my ($self, $function, $args) = @_;
  $args //= [];

  my ($op, $signature, $statements) = @$function;

  if (@$signature > 1 and @$args == 1 and $self->type($args) eq 'list') {
    $args = $args->[0];
  }

  die "TestML function expected '${\scalar @$signature}' arguments, but was called with '${\scalar @$args}' arguments"
    if @$signature != @$args;

  my $i = 0;
  for my $v (@$signature) {
    $self->{vars}{$v} = $args->[$i++];
  }

  for my $statement (@$statements) {
    $self->exec_expr($statement);
  }

  return;
}

#------------------------------------------------------------------------------
sub call_bridge {
  my ($self, $name, @args) = @_;

  if (not $self->{bridge}) {
    my $bridge_module = $ENV{TESTML_BRIDGE};
    eval "require $bridge_module; 1" or die $@;
    $self->{bridge} = $bridge_module->new;
  }

  (my $call = $name) =~ s/-/_/g;

  die "Can't find bridge function: '$name'"
    unless $self->{bridge} and $self->{bridge}->can($call);

  @args = map {$self->uncook($self->exec($_))} @args;

  my @return = $self->{bridge}->$call(@args);

  return unless @return;

  $self->cook($return[0]);
}

sub call_stdlib {
  my ($self, $name, @args) = @_;

  if (not $self->{stdlib}) {
    require TestML::StdLib;
    $self->{stdlib} = TestML::StdLib->new($self);
  }

  my $call = lc $name;
  die "Unknown TestML Standard Library function: '$name'"
    unless $self->{stdlib}->can($call);

  @args = map {$self->uncook($self->exec($_))} @args;

  $self->cook($self->{stdlib}->$call(@args));
}

#------------------------------------------------------------------------------
sub assert_eq {
  my ($self, $left, $right, $label) = @_;
  my $got = $self->{vars}{Got} = $self->exec($left);
  my $want = $self->{vars}{Want} = $self->exec($right);
  my $method = $self->get_method('==', $got, $want);
  $self->$method($got, $want, $label);
  return;
}

sub assert_str_eq_str {
  my ($self, $got, $want, $label) = @_;
  $self->testml_eq($got, $want, $self->get_label($label));
}

sub assert_num_eq_num {
  my ($self, $got, $want, $label) = @_;
  $self->testml_eq($got, $want, $self->get_label($label));
}

sub assert_bool_eq_bool {
  my ($self, $got, $want, $label) = @_;
  $self->testml_eq($got, $want, $self->get_label($label));
}


sub assert_has {
  my ($self, $left, $right, $label) = @_;
  my $got = $self->exec($left);
  my $want = $self->exec($right);
  my $method = $self->get_method('~~', $got, $want);
  $self->$method($got, $want, $label);
  return;
}

sub assert_str_has_str {
  my ($self, $got, $want, $label) = @_;
  $self->{vars}{Got} = $got;
  $self->{vars}{Want} = $want;
  $self->testml_has($got, $want, $self->get_label($label));
}

sub assert_str_has_list {
  my ($self, $got, $want, $label) = @_;
  for my $str (@{$want->[0]}) {
    $self->assert_str_has_str($got, $str, $label);
  }
}

sub assert_list_has_str {
  my ($self, $got, $want, $label) = @_;
  $self->{vars}{Got} = $got;
  $self->{vars}{Want} = $want;
  $self->testml_list_has($got->[0], $want, $self->get_label($label));
}

sub assert_list_has_list {
  my ($self, $got, $want, $label) = @_;
  for my $str (@{$want->[0]}) {
    $self->assert_list_has_str($got, $str, $label);
  }
}


sub assert_like {
  my ($self, $left, $right, $label) = @_;
  my $got = $self->exec($left);
  my $want = $self->exec($right);
  my $method = $self->get_method('=~', $got, $want);
  $self->$method($got, $want, $label);
  return;
}

sub assert_str_like_regex {
  my ($self, $got, $want, $label) = @_;
  $self->{vars}{Got} = $got;
  $self->{vars}{Want} = "/${\ $want->[1]}/";
  $want = $self->uncook($want);
  $self->testml_like($got, $want, $self->get_label($label));
}

sub assert_str_like_list {
  my ($self, $got, $want, $label) = @_;
  for my $regex (@{$want->[0]}) {
    $self->assert_str_like_regex($got, $regex, $label);
  }
}

sub assert_list_like_regex {
  my ($self, $got, $want, $label) = @_;
  for my $str (@{$got->[0]}) {
    $self->assert_str_like_regex($str, $want, $label);
  }
}

sub assert_list_like_list {
  my ($self, $got, $want, $label) = @_;
  for my $str (@{$got->[0]}) {
    for my $regex (@{$want->[0]}) {
      $self->assert_str_like_regex($str, $regex, $label);
    }
  }
}

#------------------------------------------------------------------------------
sub exec_dot {
  my ($self, @args) = @_;

  my $context = [];

  delete $self->{error};
  for my $call (@args) {
    if (not $self->{error}) {
      eval {
        if ($self->type($call) eq 'func') {
          $self->exec_func($call, $context->[0]);
          $context = [];
        }
        else {
          $context = $self->exec_expr($call, $context);
        }
      };
      if ($@) {
        $self->{error} = $self->call_stdlib('Error', "$@");
      }
      elsif ($self->{thrown}) {
        $self->{error} = $self->cook(delete $self->{thrown});
      }
    }
    else {
      if ($call->[0] eq 'Catch') {
        $context = [delete $self->{error}];
      }
    }
  }

  die "Uncaught Error: ${\ $self->{error}[1]{msg}}"
    if $self->{error};

  return @$context;
}

sub each_exec {
  my ($self, $list, $expr) = @_;
  $list = $self->exec($list);
  $expr = $self->exec($expr);

  for my $item (@{$list->[0]}) {
    $self->{vars}{_} = [$item];
    if ($self->type($expr) eq 'func') {
      if (@{$expr->[1]} == 0) {
        $self->exec_func($expr);
      }
      else {
        $self->exec_func($expr, [$item]);
      }
    }
    else {
      $self->exec_expr($expr);
    }
  }
}

sub each_pick {
  my ($self, $list, $expr) = @_;

  for my $block (@{$self->{data}}) {
    $self->{block} = $block;

    $self->exec_expr(['<>', $list, $expr]);
  }

  delete $self->{block};

  return;
}

sub pick_exec {
  my ($self, $list, $expr) = @_;

  my $pick = 1;
  for my $point (@$list) {
    if (
      ($point =~ /^\*/ and
        not exists $self->{block}{point}{substr($point, 1)}) or
      ($point =~ /^!*/) and
        exists $self->{block}{point}{substr($point, 2)}
    ) {
      $pick = 0;
      last;
    }
  }

  if ($pick) {
    if ($self->type($expr) eq 'func') {
      $self->exec_func($expr);
    }
    else {
      $self->exec_expr($expr);
    }
  }

  return;
}

sub call_func {
  my ($self, $func) = @_;
  my $name = $func->[0];
  $func = $self->exec($func);
  die "Tried to call '$name' but is not a function"
    unless defined $func and $self->type($func) eq 'func';
  $self->exec_func($func);
}

sub get_str {
  my ($self, $string) = @_;
  $self->interpolate($string);
}

sub get_hash {
  my ($self, $hash, $key) = @_;
  $hash = $self->exec($hash);
  $key = $self->exec($key);
  $self->cook($hash->[0]{$key});
}

sub get_list {
  my ($self, $list, $index) = @_;
  $list = $self->exec($list);
  return [] if not @{$list->[0]};
  $self->cook($list->[0][$index]);
}

sub get_point {
  my ($self, $name) = @_;
  $self->getp($name);
}

sub set_var {
  my ($self, $name, $expr) = @_;

  $self->setv($name, $self->exec($expr));

  return;
}

sub or_set_var {
  my ($self, $name, $expr) = @_;
  return if defined $self->{vars}{$name};

  if ($self->type($expr) eq 'func') {
    $self->setv($name, $expr);
  }
  else {
    $self->setv($name, $self->exec($expr));
  }
  return;
}

#------------------------------------------------------------------------------
sub getp {
  my ($self, $name) = @_;
  return unless $self->{block};
  my $value = $self->{block}{point}{$name};
  $self->exec($value) if defined $value;
}

sub getv {
  my ($self, $name) = @_;
  $self->{vars}{$name};
}

sub setv {
  my ($self, $name, $value) = @_;
  $self->{vars}{$name} = $value;
  return;
}

#------------------------------------------------------------------------------
sub type {
  my ($self, $value) = @_;

  return 'null' if not defined $value;

  if (not ref $value) {
    return 'num' if Scalar::Util::looks_like_number($value);
    return 'str';
  }
  return 'bool' if ref($value) eq 'boolean';
  if (ref($value) eq 'ARRAY') {
    return 'none' if @$value == 0;
    return $_ if $_ = $types->{$value->[0]};
    return 'list' if ref($value->[0]) eq 'ARRAY';
    return 'hash' if ref($value->[0]) eq 'HASH';
    return 'expr';
  }

  require XXX;
  XXX::ZZZ("Can't determine type of this value:", $value);
}

sub cook {
  my ($self, @value) = @_;

  return [] if not @value;
  my $value = $value[0];
  return undef if not defined $value;

  return $value if not ref $value;
  return [$value] if ref($value) =~ /^(?:HASH|ARRAY)$/;
  return $value if ref($value) eq 'boolean';
  return ['/', $value] if ref($value) eq 'Regexp';
  return ['!', $value] if ref($value) eq 'TestMLError';
  return $value->{func} if ref($value) eq 'TestMLFunction';
  return ['?', $value];
}

sub uncook {
  my ($self, $value) = @_;

  my $type = $self->type($value);

  return $value if $type =~ /^(?:str|num|bool|null)$/;
  return $value->[0] if $type =~ /^(?:list|hash)$/;
  return $value->[1] if $type =~ /^(?:error|native)$/;
  return TestMLFunction->new($value) if $type eq 'func';
  if ($type eq 'regex') {
    return ref($value->[1]) eq 'Regexp'
    ? $value->[1]
    : qr/${\ $value->[1]}/;
  }
  return () if $type eq 'none';

  require XXX;
  XXX::ZZZ("Can't uncook this value of type '$type':", $value);
}

#------------------------------------------------------------------------------
sub get_method {
  my ($self, $key, @args) = @_;
  my @sig = ();
  for my $arg (@args) {
    push @sig, $self->type($arg);
  }
  my $sig_str = join ',', @sig;

  my $entry = $vtable->{$key};
  my ($name, $pattern, $vtable) = @$entry;
  my $method = $vtable->{$sig_str} || do {
    $pattern =~ s/%(\d+)/$sig[$1 - 1]/ge;
    $pattern;
  };

  die "Can't resolve $name($sig_str)" unless $method;
  die "Method '$method' does not exist" unless $self->can($method);

  return $method;
}

sub get_label {
  my ($self, $label_expr) = @_;
  $label_expr //= '';

  my $label = $self->exec($label_expr);

  $label ||= $self->getv('Label') || '';

  my $block_label = $self->{block} ? $self->{block}{label} : '';

  if ($label) {
    $label =~ s/^\+/$block_label/;
    $label =~ s/\+$/$block_label/;
    $label =~ s/\{\+\}/$block_label/;
  }
  else {
    $label = $block_label;
  }

  return $self->interpolate($label, true);
}

sub interpolate {
  my ($self, $string, $label) = @_;
  # XXX Hack to see input file in label:
  $self->{vars}{File} = $ENV{TESTML_FILEVAR};

  $string =~ s/\{([\-\w]+)\}/$self->transform1($1, $label)/ge;
  $string =~ s/\{\*([\-\w]+)\}/$self->transform2($1, $label)/ge;

  return $string;
}

sub transform {
  my ($self, $value, $label) = @_;
  my $type = $self->type($value);
  if ($label) {
    if ($type =~ /^(?:list|hash)$/) {
      return encode_json($value->[0]);
    }
    else {
      $value =~ s/\n/␤/g;
      return "$value";
    }
  }
  else {
    if ($type =~ /^(?:list|hash)$/) {
      return encode_json($value->[0]);
    }
    else {
      return "$value";
    }
  }
}

sub transform1 {
  my ($self, $name, $label) = @_;
  my $value = $self->{vars}{$name} // return '';
  $self->transform($value, $label);
}

sub transform2 {
  my ($self, $name, $label) = @_;
  return '' unless $self->{block};
  my $value = $self->{block}{point}{$name} // return '';
  $self->transform($value, $label);
}

1;
