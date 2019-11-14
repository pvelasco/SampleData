## PREPROCESS DATA, including:
#   1. conversion to BIDS
#   2. Defacing
#   3. MRIQC
#   4. FMRIPrep

## Change lines for Study/subject/system. Also add lines for stim files, TSV fles, and eye tracking files. Then try running it on our sample data.


# Go!
# Sample data from subject wlsubj042, acquired on DATE!?!?!?!
#

###   Global variables:   ###

# Study/subject specific #
dcmFolder="/$(pwd)/dicoms"
studyFolder="/$(pwd)/BIDS"
subjectID=wlsubj042

# System specific #
# (These are the same for all studies/subjects):
# FreeSurfer license path:
fsLicense=/Applications/freesurfer/license.txt
# we'll be running the Docker containers as yourself, not as root:
userID=$(id -u):$(id -g)


###   Get docker images:   ###
docker pull cbinyu/heudiconv
docker pull bids/validator
docker pull cbinyu/bids_pydeface
docker pull cbinyu/mriqc
docker pull poldracklab/fmriprep:1.3.1

# Also, download a couple of scripts used to fix or clean-up things:
curl -L -o ./completeJSONs.sh https://raw.githubusercontent.com/cbinyu/misc_preprocessing/master/completeJSONs.sh
chmod 755 ./completeJSONs.sh

# Set up some derived variables that we'll use later:
fsLicenseBasename=$(basename $fsLicense)
fsLicenseFolder=${fsLicense%$fsLicenseBasename}

###   Extract DICOMs into BIDS:   ###
# The images were extracted and organized in BIDS format:
mkdir -p $studyFolder/derivatives
docker run --name heudiconv_container \
           --user $userID \
           --rm \
           --volume $dcmFolder:/dataIn:ro \
           --volume $studyFolder:/dataOut \
           cbinyu/heudiconv \
               -d /dataIn/{subject}/*/*.dcm \
               -f cbi_heuristic \
               -s ${subjectID} \
               -c dcm2niix \
               -b \
               -o /dataOut \
               --overwrite
# Then the 'IntendedFor' and 'NumberOfVolumes' field were filled:
./completeJSONs.sh ${studyFolder}/sub-${subjectID}


# We ran the BIDS-validator:
docker run --name BIDSvalidation_container \
           --user $userID \
           --rm \
           --volume $studyFolder:/data:ro \
           bids/validator \
               /data \
           > ${studyFolder}/derivatives/bids-validator_report.txt 2>&1


###   Deface:   ###
# The anatomical images were defaced using PyDeface:
docker run --name deface_container \
           --user $userID \
           --rm \
           --volume $studyFolder:/data \
           cbinyu/bids_pydeface \
               /data \
               /data/derivatives \
               participant \
               --participant_label ${subjectID}

###   MRIQC:   ###
# mriqc_reports folder contains the reports generated by 'mriqc'
docker run --name mriqc_container \
           --user $userID \
           --rm \
           --volume $studyFolder:/data \
           cbinyu/mriqc \
               /data \
               /data/derivatives/mriqc_reports \
               participant \
               --ica \
               --verbose-reports \
               --fft-spikes-detector \
               --participant_label ${subjectID}
docker run --name mriqc_container \
           --user $userID \
           --rm \
           --volume $studyFolder:/data \
           cbinyu/mriqc \
               /data \
               /data/derivatives/mriqc_reports \
               group

###   fMRIPrep:   ###
# fmriprep folder contains the reports and results of 'fmriprep'
docker run --name fmriprep_container \
           --user $userID \
           --rm \
           --volume $studyFolder:/data \
           --volume ${fsLicenseFolder}:/FSLicenseFolder:ro \
           poldracklab/fmriprep:1.3.1 \
               /data \
               /data/derivatives \
               participant \
               --fs-license-file /FSLicenseFolder/$fsLicenseBasename \
               --output-space T1w fsnative template \
               --template-resampling-grid "native" \
               --t2s-coreg \
               --participant_label ${subjectID} \
               --no-submm-recon