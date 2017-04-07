# logan
Log analyzer for log4j logs.

### Help
* `-D` : date filtering
* `-T` : time filtering
* `-S` : severity filtering
* `-M` : error messaga filtering

### Good to know:
* `-M` has to be the last option, it can contain white spaces
* The order and the multiplicity of `-D`, `-T`, `-S` are irrelevant.
    The last one will be chosen.

### Usage:
* `logan.sh -D2012-12-08` : it seeks all loglines with this match in date column
* `logan.sh -D2012-12-* -SSEVERE` : it seeks all lines in all days in `Dec.2012.` with `SEVERE` level
* `logan.sh -D2012-12-* -D2012-12-08` : it takes all lines matching on `08.Dec.2012`
* `logan.sh -T12:*:* -D2012-12-*` : it takes all lines matching on `Dec.2012` between noon and 1PM
* `logan.sh -MError message comes here` : it seeks all lines matching on `"Error message comes here"`
* `logan.sh -MError msg -D2012-12-12` : it seeks `"Error msg -D2012-12-12"`
