#!/bin/bash

#reverse of a string

[[ "$#" -lt 1 ]] && { echo "Give me a string" ; exit 100; }

input_string="$*"
length_string="${#input_string}"

for((i=$length_string-1;i>=0;i--));do
    temp=${input_string:$i:1}
    reverse_string+=$temp
done

echo "input string is $input_string"
echo "reverse string is $reverse_string"
