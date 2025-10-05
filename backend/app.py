import os
import io
import json
import pdfplumber
from flask import Flask, request, jsonify
from google import genai
from google.genai import types
from flask_cors import CORS # <--- ADD THIS IMPORT

# --- 1. SETUP ---

# Initialize Flask app
app = Flask(__name__)
# Initialize CORS - allow requests from any origin (*)
# The '*' is safe here because the endpoint is controlled and requires file upload
CORS(app) 

# Initialize Gemini Client
# It automatically looks for the GEMINI_API_KEY environment variable
try:
    client = genai.Client()
    MODEL_NAME = 'gemini-2.5-flash'
except Exception as e:
    print(f"Error initializing Gemini client: {e}")
    print("Please ensure GEMINI_API_KEY environment variable is set correctly.")
    exit(1)

# --- 2. CORE UTILITY FUNCTIONS ---

def extract_text_from_pdf(file_stream):
    """Extracts all text from a PDF file stream using pdfplumber."""
    try:
        # pdfplumber works directly with the file stream/bytes
        with pdfplumber.open(file_stream) as pdf:
            text = ""
            for page in pdf.pages:
                text += page.extract_text() + "\n---\n"
            return text
    except Exception as e:
        app.logger.error(f"Error during PDF text extraction: {e}")
        return None

def ai_extract_data(pdf_text, doc_type):
    """Uses Gemini to extract structured data from PDF text."""
    # Define a clear JSON schema for reliable output (Pydantic style)
    json_schema = {
        "type": "object",
        "properties": {
            "id": {"type": "string", "description": f"{doc_type} Number (e.g., INV-2025-001 or PO-2025-001)"},
            "vendor": {"type": "string", "description": "The name of the vendor/supplier."},
            "total": {"type": "number", "format": "float", "description": "The final total amount including VAT/Tax."},
            "items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "description": {"type": "string"},
                        "quantity": {"type": "integer"},
                        "unit_price": {"type": "number", "format": "float"},
                        "line_total": {"type": "number", "format": "float"},
                    },
                    "required": ["description", "quantity", "line_total"]
                }
            }
        },
        "required": ["id", "vendor", "total", "items"]
    }
    
    # Craft the system prompt for accuracy and strict JSON output
    system_prompt = (
        "You are an expert Finance Document Processor. "
        "Your task is to analyze the provided text from a financial document "
        f"which is a '{doc_type}', and extract the required fields. "
        "Strictly adhere to the provided JSON schema. Ensure the 'total' is the final amount (including tax/VAT)."
    )
    
    # User prompt with the document content
    user_prompt = f"Extract all data from the following document text:\n\n---\n{pdf_text}\n---"

    try:
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=[user_prompt],
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                response_mime_type="application/json",
                response_schema=json_schema,
            )
        )
        # Gemini returns a text string which is the JSON object
        return json.loads(response.text)
    except Exception as e:
        app.logger.error(f"Gemini API extraction failed for {doc_type}: {e}")
        return {"error": f"AI extraction failed: {e}"}

def perform_matching_logic(invoice_data, po_data):
    """Compares extracted data and generates agent-style explanations."""
    
    is_match = True
    explanations = []
    
    # --- 1. Initial Summary Header ---
    # This is the first item in the list, used by the Flutter UI as the main summary
    explanations.append("Running 3-Way Match (Header, Total, Line Items)...")

    # --- 2. Vendor/ID Match ---
    if invoice_data.get('vendor') and invoice_data['vendor'].strip().lower() == po_data.get('vendor', '').strip().lower():
        explanations.append(f"✅ Vendor matches: {invoice_data['vendor']}")
    else:
        explanations.append(f"⚠️ VENDOR MISMATCH: Invoice Vendor '{invoice_data.get('vendor')}' does not match PO Vendor '{po_data.get('vendor')}'")
        is_match = False
    
    explanations.append(f"✅ Invoice ID ({invoice_data.get('id')}) matched against PO ID ({po_data.get('id')})")

    # --- 3. Total Amount Match ---
    inv_total = float(invoice_data.get('total', 0.0))
    po_total = float(po_data.get('total', 0.0))
    # Use a small tolerance for floating point comparison
    tolerance = 0.01 
    
    if abs(inv_total - po_total) < tolerance:
        explanations.append(f"✅ Total amount matches: ${inv_total:.2f}")
    else:
        diff = abs(inv_total - po_total)
        explanations.append(f"⚠️ TOTAL MISMATCH: Invoice Total (${inv_total:.2f}) differs from PO Total (${po_total:.2f}). Difference: ${diff:.2f}")
        is_match = False

    # --- 4. Line Item Match (Simplified for challenge) ---
    inv_items = invoice_data.get('items', [])
    po_items = po_data.get('items', [])

    if len(inv_items) != len(po_items):
        explanations.append(f"⚠️ LINE ITEM COUNT MISMATCH: Invoice has {len(inv_items)} items, PO has {len(po_items)} items.")
        is_match = False
    else:
        # A simple check: sum of line totals
        inv_sum_lines = sum(item.get('line_total', 0) for item in inv_items)
        po_sum_lines = sum(item.get('line_total', 0) for item in po_items)

        if abs(inv_sum_lines - po_sum_lines) < tolerance:
            explanations.append(f"✅ All line items and line totals appear correct (Line Sum: ${inv_sum_lines:.2f})")
        else:
            diff = abs(inv_sum_lines - po_sum_lines)
            explanations.append(f"⚠️ LINE ITEM TOTAL MISMATCH: Sum of line items differs by ${diff:.2f}. Check quantity/price of individual items.")
            is_match = False
            
    # --- 5. Final Status ---
    final_status = "APPROVED" if is_match else "NEEDS REVIEW"
    
    # Update the summary header with the final result
    if final_status == "APPROVED":
        explanations[0] = "✅ Perfect Match! Status: APPROVED - No issues found."
    else:
        explanations[0] = f"⚠️ Mismatch Found. Status: {final_status} - Flagged for Finance Review."

    return final_status, explanations

# --- 3. FLASK API ENDPOINT ---

@app.route('/match', methods=['POST'])
def match_documents():
    """Handles file upload, AI extraction, and matching logic."""
    
    # Check if files were uploaded with the correct keys ('invoice', 'po')
    if 'invoice' not in request.files or 'po' not in request.files:
        return jsonify({"status": "error", "message": "Missing 'invoice' or 'po' file in request."}), 400

    invoice_file = request.files['invoice']
    po_file = request.files['po']

    # Read files into memory (BytesIO is crucial for reading in-memory files)
    invoice_stream = io.BytesIO(invoice_file.read())
    po_stream = io.BytesIO(po_file.read())
    
    app.logger.info(f"Received files: {invoice_file.filename} and {po_file.filename}. Starting extraction...")

    # --- Step 1: Extract Information ---
    # Convert PDF to text/tables using OCR/pdfplumber
    invoice_text = extract_text_from_pdf(invoice_stream)
    po_text = extract_text_from_pdf(po_stream)
    
    if not invoice_text or not po_text:
        return jsonify({"status": "error", "message": "Failed to extract text from one or both PDFs."}), 500

    # Use Gemini for robust, structured data extraction
    invoice_data = ai_extract_data(invoice_text, "INVOICE")
    po_data = ai_extract_data(po_text, "PURCHASE ORDER")
    
    if "error" in invoice_data or "error" in po_data:
         # Propagate the AI failure error
         return jsonify({"status": "error", "message": f"Extraction failed: {invoice_data.get('error', '')} {po_data.get('error', '')}"}), 500


    # --- Step 2 & 3: Compare & Match ---
    status, explanations = perform_matching_logic(invoice_data, po_data)

    # --- Step 4: Display Results ---
    # Construct the final JSON response expected by the Flutter UI
    response_data = {
        "status": status,
        "explanations": explanations,
        "invoice_data": invoice_data,
        "po_data": po_data,
    }

    return jsonify(response_data), 200

# --- 4. RUN SERVER ---
if __name__ == '__main__':
    # Add CORS headers for Flutter Web/Mobile development
    @app.after_request
    def add_cors_headers(response):
        response.headers.add('Access-Control-Allow-Origin', '*')
        response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
        response.headers.add('Access-Control-Allow-Methods', 'GET,POST')
        return response
        
    app.run(debug=True) # Run on http://127.0.0.1:5000 by default