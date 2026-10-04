/*
 * ghostty-swap SOURCE TARGET
 *
 * Puts SOURCE at TARGET in one rename, so TARGET is never missing, not even
 * for a moment and not after an interrupted deploy. If TARGET exists, the
 * two are exchanged (renamex_np RENAME_SWAP) and SOURCE then holds what
 * TARGET held; prints "swapped". If TARGET does not exist, SOURCE is
 * renamed there, refusing to replace anything that appeared meanwhile
 * (RENAME_EXCL); prints "moved". A rename never follows a symlink at
 * either path, so a link planted at TARGET is moved aside, not written
 * through. Both paths must be on one volume.
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: ghostty-swap SOURCE TARGET\n");
        return 2;
    }
    const char *source = argv[1];
    const char *target = argv[2];

    /* TARGET can appear or vanish between the two calls; one retry covers
     * one change, and anything busier is reported rather than chased. */
    for (int attempt = 0; attempt < 2; attempt++) {
        if (renamex_np(source, target, RENAME_SWAP) == 0) {
            puts("swapped");
            return 0;
        }
        if (errno != ENOENT)
            break;
        if (renamex_np(source, target, RENAME_EXCL) == 0) {
            puts("moved");
            return 0;
        }
        if (errno != EEXIST)
            break;
    }
    fprintf(stderr, "ghostty-swap: %s -> %s: %s\n", source, target, strerror(errno));
    return 1;
}
