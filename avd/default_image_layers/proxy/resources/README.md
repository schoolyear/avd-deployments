# Resources folder

_You can remove this file if you want_

You can put any file in this folder that you require during the image building process.
Files such as:

- MSI packages
- Scripts that are executed during session host deployment
- Scripts that are executed by the Schoolyear VDI Browser

This `resources` folder is downloaded to the image building machine and will be
deleted afterward.
If you want to make a file accessible on the session hosts, you must copy them manually.

## Merging

This `resources` folder is merged with the `resources` folders of the other layers
though the "Layered Ordering Algorithm", which is described in depth elsewhere.

Summary:

- The file structures of each layer are merged. Except for "ordered" files, any conflict results in failure.
- Ordered files have numbered prefixes to their names. These numbers can be any digit, but must be three characters.
    - `000_<filename>`: default ordering
    - `000_pre_<filename>`: prefer early ordering
    - `000_post_<filename>`: prefer later ordering
- All the ordered files in one folder get a new prefix to follow the ordering of layers.
  **Important**: This means that their filenames will change.
