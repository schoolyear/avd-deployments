# This script is executed during image build to persist the following scripts in the image:
# - sessionhost setup scripts
# - session scripts
# - user scripts

Copy-Item -Path "$env:SY_RESOURCE_FOLDER\session_scripts" -Destination "$env:SystemDrive\sy\session_scripts" -Recurse
Copy-Item -Path "$env:SY_RESOURCE_FOLDER\user_scripts" -Destination "$env:SystemDrive\sy\user_scripts" -Recurse
Copy-Item -Path "$env:SY_RESOURCE_FOLDER\sessionhost_setup_scripts" -Destination "$env:SystemDrive\sy\sessionhost_setup_scripts" -Recurse

# this line depends on the lines above to make sure the target directory exists
Copy-Item -Path "$env:SY_RESOURCE_FOLDER\base_scripts\sessionhost_setup.ps1" -Destination "$env:SystemDrive\sy"