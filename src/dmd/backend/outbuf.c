/**
 * Compiler implementation of the
 * $(LINK2 http://www.dlang.org, D programming language).
 *
 * Copyright:   Copyright (C) 1994-1998 by Symantec
 *              Copyright (C) 2000-2018 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/backend/outbuf.c, backend/outbuf.c)
 */

// Output buffer

#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <stdio.h>

#include "cc.h"

#include "outbuf.h"
#include "mem.h"

#if DEBUG
static char __file__[] = __FILE__;      // for tassert.h
#include        "tassert.h"
#else
#include        <assert.h>
#endif

Outbuffer::Outbuffer()
{
    buf = NULL;
    pend = NULL;
    p = NULL;
    origbuf = NULL;
}

Outbuffer::Outbuffer(d_size_t initialSize)
{
    buf = NULL;
    pend = NULL;
    p = NULL;
    origbuf = NULL;

    enlarge(initialSize);
}

Outbuffer::~Outbuffer()
{
    if (buf != origbuf)
    {
#if MEM_DEBUG
        mem_free(buf);
#else
        if (buf)
            free(buf);
#endif
    }
}
