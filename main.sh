#!/bin/bash

set -e
set -o pipefail
set -u

chunk_size=512

# create FAT fs in an image file
fat_sectors=128
image_file=fat.img
mkfs.vfat -C "$image_file" $fat_sectors

# copy files up to the image
mcopy -i "$image_file" testfile.pdf ::testfile.pdf
mdir -i "$image_file"

# chop image and original files into $chunk_size bytes blocks
mkdir blocks blocks/image blocks/originals
split -b $chunk_size -a 4 -d "$image_file" blocks/image/block_
for f in *.pdf
do
    split -b $chunk_size -a 4 -d "$f" blocks/originals/"$f"_
done

# find duplicate blocks
rdfind -dryrun true blocks/image/ blocks/originals/

# mark "all zero" chunk files
true > zero-chunks.txt
for b in blocks/image/block_*
do
	if cmp -s -n $chunk_size "$b" /dev/zero
	then
		echo "$b" >> zero-chunks.txt
	fi
done

# chunk files are not needed anymore
rm -r blocks

# generate mapping, subsequent blocks unmerged
cat results.txt | sed -e '/^#/d' | ./rdfindresults_to_dm_table | sort -n > unmerged.table
# join subsequent blocks
cat unmerged.table | ./merge_adjacent_ranges > merged.table
# generate mapping which concatfs consumes
[ ! -d concatfs.d ] && mkdir concatfs.d
cat merged.table | ./gen_concat_list > concatfs.d/"$image_file"
