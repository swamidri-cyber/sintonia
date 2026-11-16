"""yt-dlp como script (así la app empaquetada lo corre con su propio Python)."""
import sys

import yt_dlp

if __name__ == "__main__":
    sys.exit(yt_dlp.main())
