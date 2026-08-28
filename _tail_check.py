with open(r'd:\EkThikana_Full_Production_Starter\GOCHANO.md', 'rb') as f:
    data = f.read()
print("size:", len(data))
print("last 5 bytes:", data[-5:])