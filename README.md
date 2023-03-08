# tibber-mill-power

# What's that for?

## Get pricing via Tibber api
* inspired by https://github.com/ast0815/ha-tibber-price-graph

## Calculate plan for millheat sockets (no heater connected)
### needed packages
* jq

## Generate and upload an image to a connected tolino (via ftp)
### draw graph
#### needed packages
* gnuplot
* jq 
* imagemagick 
* ttf-dejavu
#### graph
* draw percentile line
* draw today and yesterday (only available after 13:15 CET)

### ftp upload
* will be done via ncftpput
* target is fritzbox
* user has limited access to ftp directories

## License
see [LICENSE](LICENSE) file

# References
* https://github.com/ast0815/ha-tibber-price-graph
* https://github.com/Mill-International-AS/Generation_3_REST_API/tree/release_0x220727_heaters (not in master currently)