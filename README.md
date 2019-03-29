# hackpp
A preprocessor for the Hack ASM language.

# Usage
Extract the file. (`tar xzf hackpp-<platform>.tar.gz` on Linux and OS X)

To run it, you must use the command line.
Enter the extracted directory on the command line and type the following.

On Linux:

```./hackpp-linux <filename> [-o <output-filename>]```

On OS X and Windows:

```python hackpp.py <filename> [-o <output-filename>]```

If `-o` is not passed, the output will be in `result.asm`.

# Features
## Representation of addresses and identifiers
When using macros, you can represent literals with a `:` prefix, and addresses or identifiers with an `@` prefix.
For example:
```c
// copy x to RAM[0]
#SET @0 @x
// set x to 0
#SET @x :0
// copy RAM[0] to y
#SET @y @0
```

## Macros
This is the main feature of HackPP. Macros allow you to write more code in less time, and help you to catch mistakes more quickly.

### Defining/calling functions
HackPP adds a notion of functions to Hack assembly. You define functions with the `#DEF` macro, and call them with `#CALL`. Here is an example function, which also shows how to define your entry point:
```c
#GOTO MAIN
// function definition
#DEF doNothingWith
// just copy RAM[0] to RAM[15] (the return address)
#SET @15 @0
#ENDDEF
(MAIN)
// set up parameters
#SET @0 :33
// call function
#CALL doNothingWith
// now, RAM[15] = 33
```
RAM[15] is where all return values should go after a function finishes execution.

You can also call functions with variable arguments, as you might expect.
```c
#SET @x :1
#SET @0 @x
#CALL doNothingWith
#SET @x @15
#ADD @x :1
#SET @0 @x
#CALL doNothingWith
```

### Looping and control flow
Unconditional looping is done with `#LOOP`. This is useful at the end of a program's execution. You can also break out of a loop with `#BREAK`.

```c
#SET @x :0
#LOOP
#IFGT @x :10
#BREAK
#ENDIF
#ADD @x :1
#ENDLOOP
```

While loops with meaningful comparisons (e.g. `#LOOPLT @x @y`) are also possible.
```c
#SET @x :0
#LOOPLT @x :10
#ADD @x :1
#ENDLOOP
```
This loop will also run 10 times, and the literals can be swapped out for addresses or identifiers.

Conditional branching is done with the variants of `#IF`:
* `#IFLT`: x < y
* `#IFLE`: x <= y
* `#IFEQ`: x == y
* `#IFGE`: x >= y
* `#IFGT`: x > y
* `#IFNE`: x != y

You can have mutually exclusive code branches by using the `#ELSE` macro. Example:
```c
#SET @x :2
#SET @y :3

#IFLT @x @y
#SET @z :1
#ELSE
#SET @z :0
#ENDIF
```

`!GOTO` is also a part of the language. It forces a jump to an existing label.

### Math
All math operations are performed in-place -- that is, the result is stored in the first operand.

Right now, you can only add or subtract two values. `#ADD @x :1` adds 1 to x and stores it in x. `#SUB @x :10` subtracts 10 from x and stores it in x.
