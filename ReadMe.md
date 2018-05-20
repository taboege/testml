Failing Test For New TestML Runtime
===================================

This repo has the things you need to write a new TestML runner in some
language.

# Synopsis

Run these commands:
```
git clone -b devel-new-lang git@github.com:testml-lang/testml
cd testml
source profile
testml --help
testml -R perl test1.tml
testml -R haskell test1.tml

make clean
```

# Description

This repo shows how to run testml on a sample tml file (`test1.tml`). When you
run it with `perl` you should see output like this:
```
ok 1 - Test Block 1 - 3 + 3 == 6
ok 2 - Test Block 2 - -5 + -5 == -10
ok 3 - Test Block 1 - 6 - 3 == 3
ok 4 - Test Block 2 - -10 - -5 == -5
ok 5 - Test Block 1 - 3 * 2 == 6
ok 6 - Test Block 2 - -5 * 2 == -10
ok 7 - Test Block 1 - 6 / 2 == 3
ok 8 - Test Block 2 - -10 / 2 == -5
ok 9 - Test Block 2 - -5 * 7 == -35
1..9
```

If you are not familiar with this output, it is TAP. You can read about it
here: https://testanything.org/

TestML intends to support all conceivable testing frameworks and outputs, but
TAP is easy to start with.

When you run the `testml -R haskell test1.tml` command you'll get some output
explaining your future. The file that orchestrates the Haskell runtime is
`bin/testml-haskell`.

You can review the TestML parts of another language like CoffeeScript, by
looking at these files:
```
testml/bin/testml-coffee-tap
testml/lib/coffee/testml/bridge.coffee
testml/lib/coffee/testml/run/tap.coffee
testml/lib/coffee/testml/run.coffee
testml/lib/coffee/testml/tap.coffee
testml/test/testml-bridge.coffee
```

CoffeeScript is probably the best choice because it is very easy to read and
understand.

# Your Future

You mission, should you choose to accept it, is to get the `haskell` command to
work the same as `perl`. The `testml-run-file` function in the
`bin/testml-haskell` file is passed the path of the compiled (to JSON)
test1.tml file in `$1`. There are also a bunch of `TESTML_` environment
variables to use.

The JSON data is a Lispy format that you need to evaluate. Your resulting
output should match the output of the Perl runner (shown above).
