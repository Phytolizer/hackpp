#!/usr/bin/env bash

python hackpp.py $1 > /dev/null
python Assembler.py output.asm -o own_output.hack > /dev/null
Assembler output.asm > /dev/null
diff own_output.hack output.hack