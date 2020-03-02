process abricate {
    publishDir "${params.output}/${name}/ABR-Screening", mode: 'copy', pattern: "*.tab"
    label 'abricate'
    //if (workflow.profile == 'standard' && params.fastq) { maxForks 1 }   
  input:
    tuple val(name), file(fasta) 
    each method
  output:
	  tuple val(name), val("${method}"), file("*.tab")
  script:
    """
  	abricate ${fasta} --nopath --quiet --mincov 85 --db ${method} > ${method}.tab
    """
}

process abricate_compare {
    label 'abricate'
    def random = (Math.random() + Math.random()).toString().md5().toString()
  input:
    tuple val(name), val(type), path(fasta) 
    each method
  output:
	  path("${method}_${type}_${name}.abricate_${random}")
  script:
    """
  	abricate ${fasta} --nopath --quiet --mincov 85 --db ${method} > ${method}_${type}_${name}.abricate_${random}
    """
}