#!/usr/bin/env bash

# Download bitcoin core, verify the file's sha, and extract to /usr/local/bin
download_bitcoin_core () {
	wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz \
		--no-clobber \
		--output-document=/tmp/bitcoin-25.0-x86_64-linux-gnu.tar.gz

	wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS \
		--no-clobber \
		--output-document=/tmp/SHA256SUMS

	wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc \
		--no-clobber \
		--output-document=/tmp/SHA256SUMS.asc

	cd /tmp
	if [[ $(sha256sum --ignore-missing --check SHA256SUMS) == "bitcoin-25.0-x86_64-linux-gnu.tar.gz: OK" ]]; then
		echo "Binary signature verification successful"
	fi

	tar --extract \
		--file /tmp/bitcoin-25.0-x86_64-linux-gnu.tar.gz \
		--directory /usr/local/bin/
}

download_bitcoin_core
