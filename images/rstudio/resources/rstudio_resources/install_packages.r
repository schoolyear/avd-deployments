
# Install necessary packages for creating R Markdown
install.packages(c(
    'base64enc',
    'highr',
    'htmltools',
    'knitr',
    'markdown',
    'mime',
    'rmarkdown',
    'xfun',
    'yaml',
    'magrittr',
    'stringi',
    'stringr',
    'tinytex'
), repos="https://cran.rstudio.com")

# Install tinytex, which is necessary for PDF generation
tinytex::install_tinytex()

# By default, TinyTeX is installed into the $env:HOMEUSER\AppData\Roaming directory
# we want to move it into the C:\ drive in order to access it globally for all users
tinytex::copy_tinytex(to="C:\\")