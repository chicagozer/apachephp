FROM debian:jessie

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added

ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $PATH:$HTTPD_PREFIX/bin
RUN mkdir -p "$HTTPD_PREFIX" \
	&& chown www-data:www-data "$HTTPD_PREFIX"
WORKDIR $HTTPD_PREFIX

# install httpd runtime dependencies
# https://httpd.apache.org/docs/2.4/install.html#requirements
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		libapr1 \
		libaprutil1 \
		libapr1-dev \
		libaprutil1-dev \
		libaprutil1-ldap \
		libpcre++0 \
		libssl1.0.0 \
		libperl-dev \
		libffi-dev \
		libaio1 \
		libxml2-dev \
		cpanminus \
                vim \
		unzip \
	&& rm -r /var/lib/apt/lists/*

#ENV HTTPD_VERSION 2.2.31
ENV HTTPD_VERSION 2.4.26
ENV HTTPD_BZ2_URL https://www.apache.org/dist/httpd/httpd-$HTTPD_VERSION.tar.bz2

RUN buildDeps=' \
		ca-certificates \
		curl \
		wget \
		bzip2 \
		gcc \
		libpcre++-dev \
		libssl-dev \
		make \
		xz-utils \
	' \
	set -x \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends $buildDeps \
	&& rm -r /var/lib/apt/lists/* \
	&& curl --silent -fSL "$HTTPD_BZ2_URL" -o httpd.tar.bz2 \
	&& curl --silent -fSL "$HTTPD_BZ2_URL.asc" -o httpd.tar.bz2.asc \
# see https://httpd.apache.org/download.cgi#verify
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B1B96F45DFBDCCF974019235193F180AB55D9977 \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 791485A8 \
	&& gpg --batch --verify httpd.tar.bz2.asc httpd.tar.bz2 \
	&& rm -r "$GNUPGHOME" httpd.tar.bz2.asc \
	&& mkdir -p src/httpd \
	&& tar -xvf httpd.tar.bz2 -C src/httpd --strip-components=1 \
	&& rm httpd.tar.bz2 \
	&& cd src/httpd \
	&& ./configure --enable-so --enable-ssl --prefix=$HTTPD_PREFIX --enable-mpms-shared=prefork --with-mpm=prefork --enable-mods-shared='proxy ldap authnz_ldap most' \
	&& make -j"$(nproc)" \
	&& make install \
	&& cd ../../ \
	&& rm -r src/httpd \
	&& sed -ri ' \
		s!^(\s*CustomLog)\s+\S+!\1 /proc/self/fd/1!g; \
		s!^(\s*ErrorLog)\s+\S+!\1 /proc/self/fd/2!g; \
		' /usr/local/apache2/conf/httpd.conf 

COPY httpd-foreground /usr/local/bin/

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# gpg: key 18ADD4FF: public key "Benjamin Peterson <benjamin@python.org>" imported
ENV GPG_KEY C01E1CAD5EA2C4F0B8E3571504C367C218ADD4FF

ENV PYTHON_VERSION 2.7.11

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 8.1.2

RUN set -ex \
	&& curl --silent -fSL "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" -o python.tar.xz \
	&& curl --silent -fSL "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" -o python.tar.xz.asc \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& rm -r "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python 

RUN cat python.tar.xz | tar -xJC /usr/src/python --strip-components=1
RUN rm python.tar.xz \
        \
        && cd /usr/src/python \
        && ./configure --enable-shared --enable-unicode=ucs4 \
        && make -j$(nproc) \
        && make install

RUN ldconfig \
        && curl --silent -fSL 'https://bootstrap.pypa.io/get-pip.py' | python2 \
        && pip install --no-cache-dir --upgrade pip==$PYTHON_PIP_VERSION \
        && find /usr/local -depth \
                \( \
                    \( -type d -a -name test -o -name tests \) \
                    -o \
                    \( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
                \) -exec rm -rf '{}' + \
        && rm -rf /usr/src/python ~/.cache

ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8
ENV LANGUAGE C.UTF-8

# install "virtualenv", since the vast majority of users of this image will want it
RUN pip install --no-cache-dir virtualenv

#RUN cd /tmp ; unzip /tmp/instantclient-all-linux.x64-11.2.0.4.0.zip
#RUN mkdir -p /usr/local; mv /tmp/instantclient_11_2 /usr/local ; mv /usr/local/instantclient_11_2 /usr/local/oracleclient
#RUN ln -s /usr/local/oracleclient/libclntsh.so.11.1 /usr/local/oracleclient/libclntsh.so

ENV ORACLE_HOME="/usr/local/oracleclient/"
ENV LD_LIBRARY_PATH="/usr/local/oracleclient/"


RUN cpanm -n CPAN::Meta \
        CGI \
        Net::Amazon::S3 \
        Bundle::Apache2 \
        Template \
        Template::Plugin::DBI \
        Template::Plugin::LDAP \
        ModPerl::MM \
        Redis::Cluster \
        Apache::DBI

RUN pip install paramiko
RUN pip install ftputil

## OK APP IS DONE

RUN apt-get purge -y --auto-remove $buildDeps

RUN mkdir /var/log/httpd

EXPOSE 8000
CMD ["httpd-foreground"]
