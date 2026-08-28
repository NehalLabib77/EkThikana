import os, sys, glob, time
paths = sorted(glob.glob(os.path.join(os.environ['TEMP'], 'gochano_run_p7_*.log')), key=os.path.getmtime, reverse=True)
if not paths:
    print("NO_LOG_FILES")
    sys.exit(0)
for p in paths[:5]:
    try:
        s = os.path.getsize(p)
        m = time.strftime("%H:%M:%S", time.localtime(os.path.getmtime(p)))
        print(f"{m}\t{s}\t{p}")
    except Exception as e:
        print(f"ERR {p}: {e}")