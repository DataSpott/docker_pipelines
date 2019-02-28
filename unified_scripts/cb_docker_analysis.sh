#!/usr/bin/env bash

## Docker ##
  type docker >/dev/null 2>&1 || { echo -e >&2 "${RED}Docker not found.${NC} Please run: ${GRE}sudo apt install docker.io${NC}"; exit 1; }
  # use clonal pipeline by default
    error=''
    assembly_file=''
    plasflow=''
    nano_reads=''
    fwd_reads=''
    rev_reads=''
    CPU=''
    binning=''
    tax_read=''
    sour_cluster=''
    nanoQC=''
    centrif_DB=''
    plas_centri=''
    AB_res=''
    label='results'
  # CPU cores
    CPU=$(lscpu -p | egrep -v '^#' | wc -l) # can be changed to e.g. CPU="16"
  # colours, needed for echos
    RED='\033[0;31m'
    YEL='\033[0;33m'
    NC='\033[0m'
    GRE='\033[0;32m'
    ## Parameters ##
      WORKDIRPATH=$(pwd) # for docker mountpoint (-v)
      SCRIPTNAME=$(basename -- "$0")

###############
##  Modules  ##
###############

usage()
  {
    echo "Usage:    $SCRIPTNAME [INPUT(S)]  [OPTION(S)] [ANALYSIS TOOL(S)]"
    echo "e.g.:     $SCRIPTNAME -a assembly.fa -n reads.fastq -t 20 -l first_assembly -Lk"
    echo " "
    echo "Inputs:"
    echo -e "          [-a]    ${YEL}Assembly file / Multi fasta file${NC}; .fa or .fasta"
    echo -e "          [-n]    ${YEL}Nanopore read file${NC}; .fastq"
    echo -e "          [-1]    ${YEL}Illumina fastq forward reads${NC}; .fastq or .fastq.gz"
    echo -e "          [-2]    ${YEL}Illumina fastq reverse reads${NC}; .fastq or .fastq.gz"
    echo -e "          [-s]    ${YEL}sequencing_summary.txt location${NC};name must be: sequencing_summary.txt"
    echo "Options:"
    echo -e "          [-t]    Default: ${GRE}-t ${CPU}${NC} - amount of cores"
    echo -e "          [-l]    Label added to output dir e.g. ${GRE}-l Seq_run_2018${NC}"
    echo "Analysis tools:"
    echo -e "          [-B]    metabat-checkM, metagenome binning of contig file; Input: ${YEL}-1 -2 -a${NC}"
    echo -e "          [-L]    centrifuge, tax. classif. of reads (bacteria & archaea); Input: ${YEL}-n${NC} or ${YEL}-1 -2${NC}"
    echo -e "              [-Lk]     use bacteria, viruses, human and archaea database instead ${YEL}-n ${NC}only"
    echo -e "          [-Q]    nanopore QC, QC results for reads; Input: ${YEL}-s${NC}"
    echo -e "          [-P]    plasflow, plasmid binning; Input: ${YEL}-a${NC}"
    echo -e "              [-Pc]    Additional centrifuge contig classification of plasflow results"
    echo -e "          [-S]    Sourmash, sequence clustering; Input: ${YEL}-a${NC}"
    echo -e "          [-R]    ABRicate, resistance gene screening; Input: ${YEL}-a${NC}"
    exit;
  }

centrifuge_execute()
{
  if [ -z "${centrif_DB}" ]; then
  echo "Starting centrifuge for bacteria and archaea"
  output="centrifuge_nanopore_bac.arch_${label}"
  mkdir -p $output
  docker run --rm -i --cpus="${CPU}"\
    -v $nano_path:/input \
    -v $WORKDIRPATH/${output}:/output \
    replikation/centrifuge \
    centrifuge -p $CPU -x /centrifuge/database/p_compressed -k 5 --min-hitlen 16 \
    -U /input/$nano_name -S /output/centrifuge_out.txt --report-file /output/centrifuge_out.log
    # create report for pavian
    docker run --rm -i -v $WORKDIRPATH/${output}:/output replikation/centrifuge \
    centrifuge-kreport -x /centrifuge/database/p_compressed --min-score 300 --min-length 500 /output/centrifuge_out.txt \
    > $WORKDIRPATH/${output}/${nano_name%.*}_pavian_report.csv
  echo "Results saved to $output"
else
  echo "Starting centrifuge for bacteria, viruses, human and archaea"
  output="centrifuge_nanopore_bac.arch.vir.hum_${label}"
  mkdir -p $output
  docker run --rm -i --cpus="${CPU}"\
    -v $nano_path:/input \
    -v $WORKDIRPATH/${output}:/output \
    replikation/centrifuge_all \
    centrifuge -p $CPU -x /centrifuge/database/p_compressed+h+v -k 1 --min-hitlen 16 \
    -U /input/$nano_name -S /output/centrifuge_out.txt --report-file /output/centrifuge_out.log
    # create report for pavian
  docker run --rm -i -v --cpus="${CPU}" $WORKDIRPATH/${output}:/output replikation/centrifuge_all \
    centrifuge-kreport -x /centrifuge/database/p_compressed+h+v --min-score 300 --min-length 500 /output/centrifuge_out.txt \
    > $WORKDIRPATH/${output}/${nano_name%.*}_pavian_report.csv
  echo "Results saved to $output"
fi
}

centrifuge_illumina()
{
  echo "Starting centrifuge for bacteria and archaea (illumina)"
  output="centrifuge_illumina_bac.arch_${label}"
  mkdir -p $output
  docker run --rm -i --cpus="${CPU}"\
    -v $fwd_path:/input_fwd \
    -v $rev_path:/input_rev \
    -v $WORKDIRPATH/${output}:/output \
    replikation/centrifuge \
    centrifuge -p $CPU -x /centrifuge/database/p_compressed -k 5 --min-hitlen 16 \
    -1 /input_fwd/${fwd_file} -2 /input_rev/${rev_file} -S /output/centrifuge_out.txt --report-file /output/centrifuge_out.log
    # create report for pavian
    docker run --rm -i -v $WORKDIRPATH/${output}:/output replikation/centrifuge \
    centrifuge-kreport -x /centrifuge/database/p_compressed --min-score 300 --min-length 500 /output/centrifuge_out.txt \
    > $WORKDIRPATH/${output}/${fwd_file%.*}_pavian_report.csv
  echo "Results saved to $output"
}

plasflow_execute()
{
    echo "Starting plasflow, removing contigs below 2000 bp"
    output="plasflow_${label}"
    docker run --rm -it --cpus="${CPU}"\
      -v $WORKDIRPATH/${output}:/output \
      -v $assembly_path:/input \
      replikation/plasflow \
      filter_sequences_by_length.pl -input /input/${assembly_name} \
      -output /output/${assembly_name} -thresh 2000
    docker run --rm -it --cpus="${CPU}"\
      -v $WORKDIRPATH/${output}:/output \
      replikation/plasflow \
      PlasFlow.py --input /output/${assembly_name} \
      --output /output/plasflow_predictions --threshold 0.7
    echo "Results saved to $output"
  if [ ! -z "${plas_centri}" ]; then
    echo "Starting centrifuge for bacteria and archaea on plasflow results"
    for predicted_fasta in ${output}/plasflow_predictions_*.fasta; do
      filename=$(basename $predicted_fasta)
      docker run --rm -i --cpus="${CPU}"\
        -v $WORKDIRPATH/${output}:/output \
        replikation/centrifuge \
        centrifuge -p $CPU -x /centrifuge/database/p_compressed -k 1 --min-hitlen 16 \
        -f -U /output/${filename} -S /output/centrifuge_classifcation_${filename%.fasta}.txt \
        --report-file /output/centrifuge_classifcation_${filename%.fasta}.log
    done
    echo "Taxonomic classification saved to $output"
  fi
}

QC_nanopore()
{
  echo "Starting nanopore QC"
  output="nanoporeQC_${label}"
  mkdir -p $output
  docker run --rm -it --cpus="${CPU}" \
    -v ${WORKDIRPATH}/${output}:/output \
    -v ${seqSum_path}:/QCTutorial/RawData \
    replikation/nanopore_qc \
    R --slave -e 'rmarkdown::render("Nanopore_SumStatQC_Tutorial.Rmd", output_format = "html_document", output_file = "QC_reads.html", output_dir = "/output/")'
  echo "Results saved to $output"
}

sourmash_cluster()
{
  echo "Starting sourmash clustering"
  output="sourmash_cluster_${label}"
  mkdir -p $output
  # remove .fasta from file for better picture?
  docker run --rm -it \
    -v $WORKDIRPATH/${output}:/output \
    -v $assembly_path:/input \
    replikation/sourmash \
    /bin/sh -c "cd /input/ && sourmash compute --scaled 1000 -k 31 $assembly_name -o /output/signature.sig --singleton"
  docker run --rm -it -v $WORKDIRPATH/${output}:/output replikation/sourmash \
    sourmash compare /output/signature.sig -o /output/results_sig
  docker run --rm -it -v $WORKDIRPATH/${output}:/output replikation/sourmash \
    /bin/sh -c "sourmash plot --pdf --subsample=100 --labels /output/results_sig && mv *.pdf /output/"
  echo -e "${RED}Hint: Won't plot more than 100 samples${NC}"
  }

resistance_screen()
{
  echo "Starting ABRicate resistance gene screening"
  output="ABRicate_resistances_${label}"
  mkdir -p $output
  DB_list=$(echo -e "resfinder\nncbi\ncard\nplasmidfinder\nargannot")
  while read database; do
  echo "  Screening against ${database}"
  docker run --rm \
    -v $assembly_path:/input \
    replikation/abricate \
    /input/$assembly_name --nopath --quiet --mincov 25 --db ${database} > $WORKDIRPATH/${output}/results_${database}.tab
  done <<< "$DB_list"
  docker run --rm -it \
    -v $WORKDIRPATH/${output}:/input \
    --entrypoint "/bin/sh" \
    replikation/abricate \
    -c "cd /input/ && abricate --summary results_*.tab" > $WORKDIRPATH/${output}/summary_all.tab
}

################
##  UNTESTED  ##
################

binning_execute()
{
  # untested
  echo "Starting binning with metabat"
  output="metabat_${label}"
  mkdir -p $output
  # read mapping
  docker run --rm -it --cpus="${CPU}"\
    -v $fwd_path:/input_fwd \
    -v $rev_path:/input_rev \
    -v $assembly_path:/input \
    -v $WORKDIRPATH/${output}:/output \
    --entrypoint "/bin/sh" \
    replikation/unicycler \
    -c "bowtie2-build /input/${assembly_name} /output/assembly.contigs && \
    bowtie2 -p ${CPU} -x /output/assembly.contigs -1 /input_fwd/$fwd_file -2 /input_rev/$rev_file | samtools view -bS -o binary.bam && \
    samtools sort binary.bam -o /output/${assembly_name}.srt.bam && \
    samtools index /output/${assembly_name}.srt.bam"
  # binning
  docker run --rm -it --cpus="${CPU}"\
    -v $assembly_path:/input \
    -v $WORKDIRPATH/${output}:/output \
    metabat/metabat \
    sh -c "cp /input/${assembly_name} /output/ && cd /output/ && runMetaBat.sh -m 1500 ${assembly_name} ${assembly_name}.srt.bam \
    && mv *metabat-bins1500 metabat_bins"
  # bin integrety & plotting
  docker run --rm -it --cpus="${CPU}"\
     -v $WORKDIRPATH/${output}:/output \
     replikation/checkm \
     lineage_wf -x fa /output/metabat_bins -t ${CPU} /output/checkm/
  docker run --rm -it --cpus="${CPU}"\
     -v $WORKDIRPATH/${output}:/output \
     replikation/checkm \
     bin_qa_plot -x fa /output/checkm/ /output/metabat_bins /output/plots
}

#############################
###   Start of script    ####
#############################
echo "                                               _____________________________"
echo "______________________________________________/ Created by Christian Brandt \___"
echo " "
echo -e "${YEL}$SCRIPTNAME -h ${NC}for help/usage"
echo " "
# you could add a output flag
while getopts 'a:n:1:2:s:t:l:BLSQckPRh' flag; do
    case "${flag}" in
      a) assembly_file="${OPTARG}" ;;
      1) fwd_reads="${OPTARG}" ;;
      2) rev_reads="${OPTARG}" ;;
      n) nano_reads="${OPTARG}" ;;
      s) seqSum="${OPTARG}" ;;
      t) CPU="${OPTARG}" ;;
      l) label="${OPTARG}" ;;
      B) binning='true' ;;
      L) tax_read='true';;
      S) sour_cluster='true';;
      c) plas_centri='true';;
      Q) nanoQC='true';;
      k) centrif_DB='true';;
      P) plasflow='true';;
      R) AB_res='true';;
      h) usage;;
      *) usage
         exit 1 ;;
    esac
done

# getting dir names
  assembly_dir=$(dirname "$assembly_file" 2>/dev/null)
  nano_dir=$(dirname "$nano_reads" 2>/dev/null)
  fwd_dir=$(dirname "$fwd_reads" 2>/dev/null)
  rev_dir=$(dirname "$rev_reads" 2>/dev/null)
  seqSum_dir=$(dirname "$seqSum" 2>/dev/null)
# getting absolute paths
  assembly_path=$(cd $assembly_dir 2>/dev/null && pwd)
  nano_path=$(cd "$nano_dir" 2>/dev/null && pwd)
  fwd_path=$(cd "$fwd_dir" 2>/dev/null && pwd)
  rev_path=$(cd "$rev_dir" 2>/dev/null && pwd)
  seqSum_path=$(cd "$seqSum_dir" 2>/dev/null && pwd)
# getting filename
  assembly_name=${assembly_file##*/}
  nano_name=${nano_reads##*/}
  fwd_file=${fwd_reads##*/}
  rev_file=${rev_reads##*/}

#############################
## Choose Executable(s)    ##
#############################
# Taxonomic read classification
  if [ ! -z "${tax_read}" ]; then
    if [ ! -z "${nano_reads}" ]; then centrifuge_execute ; else
      if [ ! -z "${fwd_reads}" ]; then centrifuge_illumina ; else error=true ; fi fi fi
# Nanopore QC
  if [ ! -z "${nanoQC}" ]; then
    if [ ! -z "${seqSum}" ]; then QC_nanopore ; else error=true ; fi fi
# Plasmid binning
  if [ ! -z "${plasflow}" ]; then
    if [ ! -z "${assembly_file}" ]; then plasflow_execute ; else error=true ; fi fi
# Sourmash assembly classification
  if [ ! -z "${sour_cluster}" ]; then
    if [ ! -z "${assembly_file}" ]; then sourmash_cluster ; else error=true ; fi fi
# Resistance gene screening
  if [ ! -z "${AB_res}" ]; then
    if [ ! -z "${assembly_file}" ]; then resistance_screen ; else error=true ; fi fi
# Binning
      if [ ! -z "${binning}" ]; then
          if [ ! -z "${assembly_file}" ]; then
            if [ ! -z "${fwd_reads}" ]; then binning_execute ; else error=true ; fi
          else error=true ; fi fi
# error filled
  if [ ! -z "${error}" ]; then usage ; fi
