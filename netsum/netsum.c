/*
 * Copyright (c) 2024, Jesús Daniel Colmenares Oviedo <DtxdF@disroot.org>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <err.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sysexits.h>
#include <unistd.h>

struct ipinfo {
    unsigned int cidr;
    unsigned int hosts;
    struct in_addr addr;
    struct in_addr mask;
    struct in_addr id;
    struct in_addr min;
    struct in_addr max;
    struct in_addr broadcast;
    struct in_addr wildcard;
};

union ipinfo_addr {
    uint32_t v;
    unsigned char b[4];
};

/* Calc */
static int      calc_ipinfo(const char *address, unsigned int cidr, struct ipinfo *ipdata);
static int      _calc_ipinfo(const char *address, unsigned int cidr, struct ipinfo *ipdata);
static in_addr_t    calc_mask(unsigned int cidr);
static in_addr_t    calc_netid(struct in_addr *addr, struct in_addr *mask);
static in_addr_t    calc_wildcard(struct in_addr *mask);
static in_addr_t    calc_broadcast(struct in_addr *netid, struct in_addr *wildcard);
static in_addr_t    calc_min(struct in_addr *netid);
static in_addr_t    calc_max(struct in_addr *broadcast);
static unsigned int calc_hosts(struct in_addr *wildcard);
/* Generic */
static void print_ipsum(struct ipinfo *ipdata, uint32_t n);
static void print_netaddr(struct ipinfo *ipdata);
static void print_ipaddr(struct in_addr *addr);
static int  safe_atoi(const char *s, int *ret_i);
static void usage(void);

int
main(int argc, char **argv)
{
    int c;
    int rc = 0;
    bool aflag, Nflag, nflag;
    char *address;
    int cidr = 0;
    int number = 0;
    struct ipinfo ipdata;

    address = NULL;
    aflag = Nflag = nflag = false;

    while ((c = getopt(argc, argv, "a:N:n:")) != -1) {
        switch (c) {
        case 'a':
            address = optarg;
            aflag = true;
            break;
        case 'N':
            rc = safe_atoi(optarg, &number);
            Nflag = true;
            break;
        case 'n':
            rc = safe_atoi(optarg, &cidr);
            nflag = true;
            break;
        case '?':
        default:
            usage();
        }

        if (rc != 0) {
            if (errno != 0)
                err(EX_SOFTWARE, "atol()");
            else
                errx(EX_SOFTWARE, "Could not convert %s to an integer.",
                    optarg);
        }
        
        switch (c) {
        case 'N':
            if (number < 0 || number > UINT32_MAX)
                errx(EX_DATAERR, "Invalid number, the valid ranges are: 0 - %d", UINT32_MAX);
            break;
        case 'n':
            if (cidr < 0 || cidr > 30)
                errx(EX_DATAERR, "CIDR is invalid, the valid ranges are: 0 - 30");
            break;
        }
    }

    /* Options */
    if (!aflag || !Nflag || !nflag)
        usage();
    
    if ((rc = _calc_ipinfo(address, (unsigned int)cidr, &ipdata)) != 1)
        return rc;

    printf("NETWORK=");
    print_netaddr(&ipdata);
    printf("ADDRESS=");
    print_ipsum(&ipdata, number);

    return EXIT_SUCCESS;
}

static int
calc_ipinfo(const char *address, unsigned int cidr, struct ipinfo *ipdata)
{
    int rc;

    if ((rc = inet_pton(AF_INET, address, &ipdata->addr)) != 1)
        return rc;

    ipdata->cidr = cidr;
    ipdata->mask.s_addr = calc_mask(cidr);
    ipdata->id.s_addr = calc_netid(&ipdata->addr, &ipdata->mask);
    ipdata->wildcard.s_addr = calc_wildcard(&ipdata->mask);
    ipdata->broadcast.s_addr = calc_broadcast(&ipdata->id, &ipdata->wildcard);
    ipdata->min.s_addr = calc_min(&ipdata->id);
    ipdata->max.s_addr = calc_max(&ipdata->broadcast);
    ipdata->hosts = calc_hosts(&ipdata->wildcard);

    return rc;
}

static int
_calc_ipinfo(const char *address, unsigned int cidr, struct ipinfo *ipdata)
{
    int rc = calc_ipinfo(address, cidr, ipdata);
    switch (rc) {
    case -1:
        err(EX_SOFTWARE, "calc_ipinfo()");
        break;
    case 0:
        errx(EX_DATAERR, "Bad IPv4 address: %s",
            address);
        break;
    }

    return rc;
}

static in_addr_t
calc_mask(unsigned int cidr)
{
    return htonl(0xffffffff << (32 - cidr));
}

static in_addr_t
calc_netid(struct in_addr *addr, struct in_addr *mask)
{
    return addr->s_addr & mask->s_addr;
}

static in_addr_t
calc_wildcard(struct in_addr *mask)
{
    return ~mask->s_addr;
}

static in_addr_t
calc_broadcast(struct in_addr *netid, struct in_addr *wildcard)
{
    return netid->s_addr | wildcard->s_addr;
}

static in_addr_t
calc_min(struct in_addr *netid)
{
    return htonl(ntohl(netid->s_addr) + 1);
}

static in_addr_t
calc_max(struct in_addr *broadcast)
{
    return htonl(ntohl(broadcast->s_addr) - 1);
}

static unsigned int
calc_hosts(struct in_addr *wildcard)
{
    return ntohl(wildcard->s_addr) - 1;
}

static void
print_ipsum(struct ipinfo *ipdata, uint32_t n)
{
    struct in_addr addr;
    uint32_t cur, end;

    cur = ntohl(ipdata->min.s_addr) + n;
	end = ntohl(ipdata->max.s_addr);

    if (cur > end)
        errx(EX_DATAERR, "The maximum number of IP addresses has been reached");

    addr.s_addr = htonl(cur);

    print_ipaddr(&addr);
}

static void
print_netaddr(struct ipinfo *ipdata)
{
    struct in_addr addr;
    addr.s_addr = ipdata->id.s_addr;

    print_ipaddr(&addr);
}

static void
print_ipaddr(struct in_addr *a)
{
    union ipinfo_addr ipnet_addr;
    ipnet_addr.v = a->s_addr;

    printf("%u.%u.%u.%u\n",
        ipnet_addr.b[0],
        ipnet_addr.b[1],
        ipnet_addr.b[2],
        ipnet_addr.b[3]);
}

static int
safe_atoi(const char *s, int *ret_i)
{
    char *x = NULL;
    long l;

    errno = 0;
    l = strtol(s, &x, 0);

    if (!x || x == s || *x || errno)
        return errno > 0 ? -errno : -EINVAL;

	if ((long)(int)l != l)
		return -ERANGE;
    
    *ret_i = (int)l;
    return 0;
}

static void
usage(void)
{
    errx(EX_USAGE, "%s",
        "usage: netsum -a address -N number -n cidr");
}
