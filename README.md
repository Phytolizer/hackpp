# hackpp
A preprocessor for Hack.

# Dependencies
Ruby version 2.2 or higher

# Usage
To compile to Hack ASM:
`ruby hackpp.rb <filename> [-o <output-filename>]`

# Macros
There aren't many macros supported right now (only defining and calling functions), but support for more will be added with time.
## Defining functions
To write a function, type the following.
```c
!DEF myFunction x, y, z
// assembly code for the function goes here
!ENDDEF
```
Parameters will be stored in the RAM addresses 0, 1, 2, etc. in the order they appear.

## Calling functions
To call your function, just type:
```c
!CALL myFunction 4, 26, 83
```
As of right now, parameters can only be constants. Support for variable parameters will be added in the future.

The return value will be in RAM address 15.
