#!/bin/bash
# License: MIT. See license file in root directory
# Copyright(c) JetsonHacks (2017-2019)

OPENCV_VERSION=4.9.0
INSTALL_DIR=/usr/local
# GPU ARCH
ARCH_BIN=8.7
# Download the opencv_extras repository
# If you are installing the opencv testdata, ie
#  OPENCV_TEST_DATA_PATH=../opencv_extra/testdata
# Make sure that you set this to YES
# Value should be YES or NO
DOWNLOAD_OPENCV_EXTRAS=NO
# Source code directory
OPENCV_SOURCE_DIR=$PWD
WHEREAMI=$PWD
# NUM_JOBS is the number of jobs to run simultaneously when using make
# This will default to the number of CPU cores (on the Nano, that's 4)
# If you are using a SD card, you may want to change this
# to 1. Also, you may want to increase the size of your swap file
NUM_JOBS=$(nproc)

CLEANUP=true

PACKAGE_OPENCV="-D CPACK_BINARY_DEB=ON"

function usage
{
    echo "usage: ./buildOpenCV.sh [[-s sourcedir ] | [-h]]"
    echo "-s | --sourcedir   Directory in which to place the opencv sources (default $HOME)"
    echo "-i | --installdir  Directory in which to install opencv libraries (default /usr/local)"
    echo "--no_package       Do not package OpenCV as .deb file (default is true)"
    echo "--cuda             Build for the cuda"
    echo "--depends          Install dependencies and exit"
    echo "-h | --help  This message"
}

# Iterate through command line inputs
while [ "$1" != "" ]; do
    case $1 in
        -s | --sourcedir )      shift
				OPENCV_SOURCE_DIR=$1
                                ;;
        -i | --installdir )     shift
                                INSTALL_DIR=$1
                                ;;
        --no_package )          PACKAGE_OPENCV=""
                                ;;
        --cuda )                BUILD_CUDA=1
                                ;;
        --depends )             INSTALL_DEPENDS=1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

CMAKE_INSTALL_PREFIX=$INSTALL_DIR

# Print out the current configuration
echo "Build configuration: "
echo " Build for CUDA: $BUILD_CUDA"
echo " OpenCV binaries will be installed in: $CMAKE_INSTALL_PREFIX"
echo " OpenCV Source will be installed in: $OPENCV_SOURCE_DIR"
if [ "$PACKAGE_OPENCV" = "" ] ; then
   echo " NOT Packaging OpenCV"
else
   echo " Packaging OpenCV"
fi

if [ $DOWNLOAD_OPENCV_EXTRAS == "YES" ] ; then
 echo "Also downloading opencv_extras"
fi

# Repository setup
sudo apt-get update

# Download dependencies for the desired configuration
cd $WHEREAMI
sudo apt-get install -y \
    build-essential \
    cmake \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libeigen3-dev \
    libgtk2.0-dev \
    libgtk-3-dev \
    libjpeg-dev \
    libpng-dev \
    libpostproc-dev \
    libswscale-dev \
    libtbb-dev \
    libv4l-dev \
    libxvidcore-dev \
    zlib1g-dev \
    pkg-config

# We will be supporting OpenGL, we need a little magic to help
cd /usr/local/cuda/include

# Python 3
sudo apt-get install -y python3-dev python3-numpy python3-py python3-pytest python3-pip python3-numpy

# GStreamer support
sudo apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

if [[ -n $BUILD_CUDA ]]; then
    echo "Building for CUDA"
    #sudo apt-get install -y nvidia-cuda
    CUDA_ENABLED=ON
else
    echo "Building for PC"
    sudo apt-get install -y pipenv
    CUDA_ENABLED=OFF
fi

if [[ -z $INSTALL_DEPENDS ]]; then

    cd $OPENCV_SOURCE_DIR
    git clone --branch "$OPENCV_VERSION" --depth 1 https://github.com/opencv/opencv.git
    git clone --branch "$OPENCV_VERSION" --depth 1 https://github.com/opencv/opencv_contrib.git
    cd opencv
    git checkout $OPENCV_VERSION
    cd ../opencv_contrib
    git checkout $OPENCV_VERSION

    if [ $DOWNLOAD_OPENCV_EXTRAS == "YES" ] ; then
     echo "Installing opencv_extras"
     # This is for the test data
     cd $OPENCV_SOURCE_DIR
     git clone https://github.com/opencv/opencv_extra.git
     cd opencv_extra
     git checkout -b v${OPENCV_VERSION} ${OPENCV_VERSION}
    fi

    # Create the build directory and start cmake
    cd $OPENCV_SOURCE_DIR/opencv
    mkdir build
    cd build

    echo $PWD
    time cmake -D CMAKE_BUILD_TYPE=RELEASE \
          -D CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX} \
          -D WITH_CUDA=${CUDA_ENABLED} \
          -D CUDA_ARCH_BIN="" \
          -D CUDA_ARCH_PTX=${ARCH_BIN} \
          -D ENABLE_FAST_MATH=ON \
          -D CUDA_FAST_MATH=ON \
          -D WITH_CUBLAS=ON \
          -D WITH_LIBV4L=ON \
          -D WITH_V4L=ON \
          -D WITH_GSTREAMER=ON \
          -D WITH_GSTREAMER_0_10=OFF \
          -D WITH_QT=ON \
          -D WITH_OPENGL=ON \
          -D BUILD_opencv_python2=ON \
          -D BUILD_opencv_python3=ON \
          -D BUILD_TESTS=OFF \
          -D BUILD_PERF_TESTS=OFF \
          -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
          $"PACKAGE_OPENCV" \
          ../

    if [ $? -eq 0 ] ; then
      echo "CMake configuration make successful"
    else
      # Try to make again
      echo "CMake issues " >&2
      echo "Please check the configuration being used"
      exit 1
    fi

    # Consider the MAXN performance mode if using a barrel jack on the Nano
    time make -j$NUM_JOBS
    if [ $? -eq 0 ] ; then
      echo "OpenCV make successful"
    else
      # Try to make again; Sometimes there are issues with the build
      # because of lack of resources or concurrency issues
      echo "Make did not build " >&2
      echo "Retrying ... "
      # Single thread this time
      make
      if [ $? -eq 0 ] ; then
        echo "OpenCV make successful"
      else
        # Try to make again
        echo "Make did not successfully build" >&2
        echo "Please fix issues and retry build"
        exit 1
      fi
    fi

    echo "Installing ... "
    sudo make install/strip
    sudo ldconfig
    if [ $? -eq 0 ] ; then
       echo "OpenCV installed in: $CMAKE_INSTALL_PREFIX"
    else
       echo "There was an issue with the final installation"
       exit 1
    fi

    # If PACKAGE_OPENCV is on, pack 'er up and get ready to go!
    # We should still be in the build directory ...
    if [ "$PACKAGE_OPENCV" != "" ] ; then
       echo "Starting Packaging"
       sudo ldconfig
       time sudo make package -j$NUM_JOBS
       if [ $? -eq 0 ] ; then
         echo "OpenCV make package successful"
       else
         # Try to make again; Sometimes there are issues with the build
         # because of lack of resources or concurrency issues
         echo "Make package did not build " >&2
         echo "Retrying ... "
         # Single thread this time
         sudo make package
         if [ $? -eq 0 ] ; then
           echo "OpenCV make package successful"
         else
           # Try to make again
           echo "Make package did not successfully build" >&2
           echo "Please fix issues and retry build"
           exit 1
         fi
       fi
    fi

    # Install the Python environment
    if [[ -z BUILD_XAVIER ]]; then
        pipenv update
    fi

    # check installation
    IMPORT_CHECK="$(python -c "import cv2 ; print cv2.__version__")"
    if [[ $IMPORT_CHECK != *$OPENCV_VERSION* ]]; then
      echo "There was an error loading OpenCV in the Python sanity test."
      echo "The loaded version does not match the version built here."
      echo "Please check the installation."
      echo "The first check should be the PYTHONPATH environment variable."
    fi
elif [[ -n $BUILD_XAVIER ]]; then
    echo "Extracting OpenCV to install directory"
    tar -xf OpenCV-4.5.4-dirty-aarch64.tar.gz
    cd OpenCV-4.5.4-dirty-aarch64
    sudo cp -r * /usr/local
    sudo ldconfig
fi
