@main
0;JMP

(myFunction)

@15
M = 0
@ret
A = M
0;JMP

(main)
@3
M = 1
@ret1
D=A
@ret
M=D
@myFunction
0;JMP
(ret1)

(loop1)
@4
M = 1
@endloop1
0;JMP
@loop1
0;JMP
(endloop1)
