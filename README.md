# hackpp
A preprocessor for Hack.

# Usage
To compile to Hack ASM:
`ruby hackpp.rb <filename> [-o <output-filename>]`
If `-o` is not passed, the output will be in `result.asm`.

# Features
## Representation of literals, addresses, and identifiers
When using macros, you can represent literals with a `$` prefix, addresses with an `@` prefix, and identifiers with no prefix.
For example:
```c
// copy x to RAM[0]
!SET @0 x
// set x to 0
!SET x $0
// copy RAM[0] to y
!SET y @0
```

## Macros
This is the main feature of HackPP. Macros allow you to write more code in less time, and help you to catch mistakes more quickly.

### Defining/calling functions
HackPP adds a notion of functions to Hack assembly. You define functions with the `!DEF` macro, and call them with `!CALL`. Here is an example function, which also shows how to define your entry point:
```c
!GOTO MAIN
!DEF doNothingWith x
!SET @15 @0
!ENDDEF
(MAIN)
!CALL doNothingWith $33
// now, RAM[15] = 33
```
RAM[15] is where all return values go after a function finishes execution.

You can also call functions with variable arguments, as you might expect.
```c
!SET x $1
!CALL doNothingWith x
!SET x @15
!ADD x $1
!CALL doNothingWith x
```

### Looping and control flow
Unconditional looping is done with `!LOOP`. This is useful at the end of a program's execution.

`!WHILENZ` will loop its body until its argument is zero. `!WHILEZR` does the opposite.
Here is a loop that will run 10 times:
```c
!SET x $9
!WHILENZ x
!SUB x $1
!ENDWHILE
```
While loops with more meaningful comparisons (e.g. `!WHILELT x y`) are also possible.
```c
!SET x $0
!WHILELT x $10
!ADD x $1
!ENDWHILE
```
This loop will also run 10 times, and the literals can be swapped out for addresses or identifiers.

`!GOTO` is also a part of the language. It forces a jump to an existing label.

### Math
All math operations are performed in-place -- that is, the result is stored in the first operand.

Right now, you can only add or subtract two values. `!ADD x $1` adds 1 to x and stores it in x. `!SUB x $10` subtracts 10 from x and stores it in x.
