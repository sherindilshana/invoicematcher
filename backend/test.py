import requests

# Upload invoice
files = {'file': open('uploads/sample_invoice.pdf', 'rb')}

resp = requests.post("http://127.0.0.1:5000/upload_invoice", files=files)
invoice_data = resp.json()
print("Invoice:", invoice_data)

# Upload PO
files = {'file': open('uploads/sample_po.pdf', 'rb')}
resp = requests.post("http://127.0.0.1:5000/upload_po", files=files)
po_data = resp.json()
print("PO:", po_data)

# Match invoice & PO
resp = requests.post("http://127.0.0.1:5000/match", json={"invoice": invoice_data, "po": po_data})
print("Match Result:", resp.json())
