#!/usr/bin/env bash
set -euo pipefail


if [[ -d ./logs ]]; then
	exec > ./logs/log 
       	 size=$(docker compose exec Nginx du -sh /var/cache/nginx/osm| awk '{print $1}')
	 sum=$(docker compose exec Nginx find /var/cache/nginx/osm -type f | wc -l)
	echo "SIZE $size"
        echo "Tiles $sum"
else 
	echo "The directory was not found"
fi
           


