#! /usr/bin/env nextflow

greetings = params.input.toLowerCase().split(',')
System.out.println(greetings.size())
System.out.println(greetings)
greeting_ch = Channel.from(greetings)


process splitLetters{

    container 'ubuntu'

    input:
    val x

    output:
    path 'chunk_*'

    """
    printf '$x' | split -b 6 - chunk_
    """
}

process convertToUpper{

    container 'ubuntu'

    input:
    file x

    output:
    stdout

    """
    cat $x | tr '[a-z]' '[A-Z]'
    """
}

workflow{
    words_ch = splitLetters(greeting_ch)
    result_ch = convertToUpper(words_ch.flatten())
    result_ch.view{it}
}
