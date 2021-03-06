#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################
# STOR_VHDXResize_PartitionDisk.sh
# Description:
#     This script will verify if you can create, format, mount, perform
#     read/write operation, unmount and deleting a partition on a resized
#     VHDx file
#     Hyper-V setting pane. The test performs the following steps
#
#    1. Make sure we have a constants.sh file.
#    2. Creates partition
#    3. Creates filesystem
#    4. Performs read/write operations
#    5. Unmounts partition
#    6. Deletes partition
#
########################################################################

ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error while performing the test

CONSTANTS_FILE="constants.sh"

LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}    # To add the timestamp to the log file
}

cd ~

UpdateTestState()
{
    echo $1 > $HOME/state.txt
}

if [ -e ~/summary.log ]; then
    LogMsg "Info: Cleaning up previous copies of summary.log"
    rm -rf ~/summary.log
fi

LogMsg "Info: Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING

# Source the constants file
if [ -e ~/${CONSTANTS_FILE} ]; then
    source ~/${CONSTANTS_FILE}
else
    msg="Error: no ${CONSTANTS_FILE} file"
    echo $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

#
# Make sure constants.sh contains the variables we expect
#
if [ "${TC_COVERED:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Error: The test parameter TC_COVERED is not defined in ${CONSTANTS_FILE}"
    echo $msg >> ~/summary.log
fi

#
# Echo TCs we cover
#
echo "Covers ${TC_COVERED}" > ~/summary.log

if [ "${fileSystems:-UNDEFINED}" = "UNDEFINED" ]; then
    msg="Error: The test parameter fileSystems is not defined in constants file."
    LogMsg "$msg"
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi

#
# Verify if guest sees the new drive
#
if [ ! -e "/dev/sdb" ]; then
    msg="Error: The Linux guest cannot detect the drive"
    LogMsg $msg
    echo $msg >> ~/summary.log
    UpdateTestState $ICA_TESTABORTED
    exit 30
fi
LogMsg "Info: The Linux guest detected the drive"

#Prepare Read/Write script for execution
dos2unix STOR_VHDXResize_ReadWrite.sh
chmod +x STOR_VHDXResize_ReadWrite.sh

#If the script is being run a second time modify the following variables
if [ "$rerun" = "yes" ]; then
    LogMsg "Info: Second pass of the script."
    testPartition="/dev/sdb2"
    fdiskOption=2
else
    testPartition="/dev/sdb1"
    fdiskOption=1
fi

count=0
for fs in "${fileSystems[@]}"; do

    # Create the new partition
    # delete partition firstly maily used if partition size >2TB, after use parted
    # to rm partition, still can show in fdisk -l even it does not exist in fact.
    (echo d; echo w) | fdisk /dev/sdb 2> /dev/null
    (echo n; echo p; echo $fdiskOption; echo ; echo ;echo w) | fdisk /dev/sdb 2> /dev/null
    if [ $? -gt 0 ]; then
        LogMsg "Error: Failed to create partition"
        echo "Error: Creating partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Info: Partition created"
    sleep 5

    # Format the partition
    LogMsg "Info: Start testing filesystem: $fs"
    command -v mkfs.$fs
    if [ $? -ne 0 ]; then
        echo "Error: File-system tools for $fs not present. Skipping filesystem $fs.">> ~/summary.log
        LogMsg "Error: File-system tools for $fs not present. Skipping filesystem $fs."
        count=`expr $count + 1`
    else
        #Use -f option for xfs filesystem, but ignore parameter for other filesystems
        option=""
        if [ "$fs" = "xfs" ]; then
            option="-f"
        fi
        mkfs -t $fs $option $testPartition 2> ~/summary.log
        if [ $? -ne 0 ]; then
            LogMsg "Error: Failed to format partition with $fs"
            echo "Error: Formating partition: Failed with $fs" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
        LogMsg "Info: Successfully formated partition with $fs"
    fi

    if [ $count -eq ${#fileSystems[@]} ]; then
        LogMsg "Error: Failed to format partition with ${fileSystems[@]} "
        echo "Error: Formating partition: Failed with all filesystems proposed." >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi

    # Mount partition
    if [ ! -e "/mnt" ]; then
        mkdir /mnt 2> ~/summary.log
        if [ $? -ne 0 ]; then
            LogMsg "Error: Failed to create mount point"
            echo "Error: Creating mount point: Failed" >> ~/summary.log
            UpdateTestState $ICA_TESTFAILED
            exit 10
        fi
        LogMsg "Info: Mount point /dev/mnt created"
    fi

    mount $testPartition /mnt 2> ~summary.log
    if [ $? -ne 0 ]; then
        LogMsg "Error: Failed to mount partition"
        echo "Error: Mounting partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Info: Partition mount successful"

    # Read/Write mount point
    ./STOR_VHDXResize_ReadWrite.sh

    umount /mnt
    if [ $? -ne 0 ]; then
        LogMsg "Error: Failed to unmount partition"
        echo "Error: Unmounting partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Info: Unmount partition successful"

    (echo d; echo w) | fdisk /dev/sdb 2> /dev/null
    if [ $? -ne 0 ]; then
        LogMsg "Error: Failed to delete partition"
        echo "Error: Deleting partition: Failed" >> ~/summary.log
        UpdateTestState $ICA_TESTFAILED
        exit 10
    fi
    LogMsg "Info: Succesfully deleted partition"

done

UpdateTestState $ICA_TESTCOMPLETED
exit 0;
