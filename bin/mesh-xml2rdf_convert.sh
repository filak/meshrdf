#!/bin/bash
#
# This script will convert all of the MeSH XML to RDF, assuming that your machine has
# enough memory and resources.  It will also copy over the vocabulary and void files.
# This script assumes that it is in the `bin` subdirectory of the clone of the 
# hhs/meshrdf repository, and it looks for some other files accordingly.
#
# The environment variable $MESHRDF_HOME is used to determine the `data` and `out`
# directories. 
#
# It is parameterized according to the following environment variables:
# - MESHRDF_YEAR - default is "2015". Set this to override the *source* data. In other
#   words, this is used to determine which XML files are used as input.
# - MESHRDF_URI_YEAR
#   By default:
#     - the generated URIs will not include the year,
#     - the output file will be named mesh.nt, and
#     - it will be put into the output directory $MESHRDF_HOME/out
#   If this is set to "yes", then:
#     - the generated URIs will include the year,
#     - the output file will be have the name meshYYYY.nt, and
#     - it will be put into the output directory $MESHRDF_HOME/out/YYYY


# Change directory to the repository root
if hash greadlink 2>/dev/null; then
    READLINK=greadlink
else
    READLINK=readlink
fi
cd $($READLINK -e `dirname $0`/..)

OASIS_CATALOG=""
MESH_JAVA_OPTS="-Xms4g -Xmx4g"

while getopts "h:j:r:y:x:o:c:u" opt; do
  case $opt in
    h) export MESHRDF_HOME=$OPTARG ;;
    j) export SAXON_JAR=$OPTARG ;;
    r) export RESOLVER_JAR=$OPTARG ;;
    y) export MESHRDF_YEAR=$OPTARG ;; 
    c) export OASIS_CATALOG=$OPTARG ;;
    u) export MESHRDF_URI_YEAR="yes" ;;
    o) export OUTFILE_FORCE=$OPTARG ;;
    x) export MESH_JAVA_OPTS=$OPTARG ;;
    *) echo "Usage: $0 [-h mesh-rdf-home] [-j saxon-jar-path] [-r resolver-jar-path] [-c xml-catalog-path]  [-x mesh_java_opts] [-y year ]" 1>&2 ; exit 1 ;;
  esac
done
shift $(($OPTIND - 1))

# Check for some needed environment variables
if [ -z "$MESHRDF_HOME" ]; then
    echo "Please define MESHRDF_HOME environment variable" 1>&2
    exit 1
fi

if [ -z "$SAXON_JAR" ]; then
    echo "Please define SAXON_JAR environment variable" 1>&2
    exit 1
fi

# NOTE: will be the classpath for running Saxon, we may need resolver
_CP="$SAXON_JAR"

# Can override default year with MESHRDF_YEAR environment variable
YEAR=${MESHRDF_YEAR:-2026}

# Set the output file name, and the parameter that controls the RDF URIs,
# according to whether or not MESHRDF_URI_YEAR is "yes"
if [ "$MESHRDF_URI_YEAR" = "yes" ]; then
    OUTDIR=$MESHRDF_HOME/out/$YEAR
    OUTFILE=$OUTDIR/mesh$YEAR
    URI_YEAR_PARAM=uri-year-segment=$YEAR
    URI_PREFIX="http://id.nlm.nih.gov/mesh/$YEAR"
else
    OUTDIR=$MESHRDF_HOME/out
    OUTFILE=$OUTDIR/mesh
    URI_YEAR_PARAM=
    URI_PREFIX="http://id.nlm.nih.gov/mesh"
fi

if [ -n "$OASIS_CATALOG" ]; then
    if [ -z "$RESOLVER_JAR" ]; then
        echo "Please define RESOLVER_JAR environment variable to use -c for XML Catalog" 1>&2
        exit 1
    fi
    OASIS_CATALOG_ARG="-catalog:$OASIS_CATALOG"
    _CP="$SAXON_JAR:$RESOLVER_JAR"
else
    OASIS_CATALOG_ARG=""
fi
    

if [ -n "$OUTFILE_FORCE" ]; then
    OUTFILE=$OUTFILE_FORCE
fi


# Do the conversions

echo Creating output dir: $OUTDIR

mkdir -p $OUTDIR

echo URI_PREFIX: $URI_PREFIX

echo Converting qual$YEAR.xml

java $MESH_JAVA_OPTS -cp "$_CP" net.sf.saxon.Transform -s:"$MESHRDF_HOME/data/qual$YEAR.xml" \
    -xsl:xslt/qual.xsl $OASIS_CATALOG_ARG $URI_YEAR_PARAM > "$OUTFILE-dups.nt"
if [ $? -ne 0 ]; then
    echo "Error converting $MESHRDF_HOME/data/qual$YEAR.xml" 1>&2
    exit 1
fi

echo Converting desc$YEAR.xml

java $MESH_JAVA_OPTS -cp "$_CP" net.sf.saxon.Transform -s:"$MESHRDF_HOME/data/desc$YEAR.xml" \
    -xsl:xslt/desc.xsl $OASIS_CATALOG_ARG $URI_YEAR_PARAM >> "$OUTFILE-dups.nt"
if [ $? -ne 0 ]; then
    echo "Error converting $MESHRDF_HOME/data/desc$YEAR.xml" 1>&2
    exit 1
fi

echo Converting supp$YEAR.xml

java $MESH_JAVA_OPTS -cp "$_CP" net.sf.saxon.Transform -s:"$MESHRDF_HOME/data/supp$YEAR.xml" \
    -xsl:xslt/supp.xsl $OASIS_CATALOG_ARG $URI_YEAR_PARAM >> "$OUTFILE-dups.nt"
if [ $? -ne 0 ]; then
    echo "Error converting $MESHRDF_HOME/data/supp$YEAR.xml" 1>&2
    exit 1
fi

echo Deduplicating $OUTFILE-dups.nt

sort -u -T"$OUTDIR" "$OUTFILE-dups.nt" > "$OUTFILE.nt"
if [ $? -ne 0 ]; then
    echo "Error deduplicating $OUTFILE-dups.nt" 1>&2
    exit 1
fi

echo Compressing $OUTFILE.nt

gzip -c "$OUTFILE.nt" > "$OUTFILE.nt.gz"
if [ $? -ne 0 ]; then
    echo "Error compressing $OUTFILE.nt" 1>&2
    exit 1
fi

echo "Finished !"

