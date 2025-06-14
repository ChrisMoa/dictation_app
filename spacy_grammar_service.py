from flask import Flask, request, jsonify
import spacy
import re
from typing import List, Dict, Any

app = Flask(__name__)

# Load the German language model
try:
    nlp = spacy.load("de_core_news_lg")
except OSError:
    print("Downloading German language model...")
    spacy.cli.download("de_core_news_lg")
    nlp = spacy.load("de_core_news_lg")

# Common German grammar rules
GRAMMAR_RULES = {
    "capitalization": [
        (r'\b(ich|du|er|sie|es|wir|ihr|sie)\b', lambda m: m.group(0).lower()),
        (r'^[a-z]', lambda m: m.group(0).upper()),  # Capitalize first letter
    ],
    "punctuation": [
        (r'\s+([.,!?])', r'\1'),  # Remove spaces before punctuation
        (r'([.,!?])([^\s])', r'\1 \2'),  # Add space after punctuation
    ]
}

def check_grammar(text: str) -> Dict[str, Any]:
    doc = nlp(text)
    errors = []
    corrected_text = text
    
    # Check for basic grammar issues
    for token in doc:
        # Check capitalization
        if token.pos_ == "PROPN" and not token.text[0].isupper():
            errors.append({
                "offset": token.idx,
                "length": len(token.text),
                "message": "Proper noun should be capitalized",
                "category": "Capitalization",
                "replacements": [token.text.capitalize()],
                "ruleId": "capitalization"
            })
            corrected_text = corrected_text[:token.idx] + token.text.capitalize() + corrected_text[token.idx + len(token.text):]
        
        # Check for common German grammar patterns
        if token.dep_ == "aux" and token.text.lower() == "sein" and token.head.pos_ == "VERB":
            if not any(t.text.lower() == "werden" for t in token.head.children):
                errors.append({
                    "offset": token.idx,
                    "length": len(token.text),
                    "message": "Consider using 'werden' with 'sein' in passive voice",
                    "category": "Grammar",
                    "replacements": ["werden"],
                    "ruleId": "passive_voice"
                })

    # Apply common grammar rules
    for rule_type, rules in GRAMMAR_RULES.items():
        for pattern, replacement in rules:
            if isinstance(replacement, str):
                corrected_text = re.sub(pattern, replacement, corrected_text)
            else:
                corrected_text = re.sub(pattern, lambda m: replacement(m), corrected_text)

    # Calculate confidence based on number of errors
    word_count = len([token for token in doc if not token.is_punct])
    error_count = len(errors)
    confidence = 1.0 - (error_count / max(word_count, 1))
    confidence = max(0.0, min(1.0, confidence))

    return {
        "originalText": text,
        "correctedText": corrected_text,
        "confidence": confidence,
        "errors": errors,
        "correctionMethod": "SpaCy Grammar Checker"
    }

@app.route('/check', methods=['POST'])
def check_text():
    data = request.get_json()
    if not data or 'text' not in data:
        return jsonify({"error": "No text provided"}), 400
    
    result = check_grammar(data['text'])
    return jsonify(result)

if __name__ == '__main__':
    app.run(port=5000) 