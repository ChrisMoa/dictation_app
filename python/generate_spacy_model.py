# generate_spacy_model.py
import spacy
import json
import tensorflow as tf
import numpy as np
from tensorflow import keras
from tensorflow.keras import layers
import os

# Configure GPU memory growth
gpus = tf.config.experimental.list_physical_devices('GPU')
if gpus:
    try:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
        print(f"Configured {len(gpus)} GPU(s) for memory growth")
    except RuntimeError as e:
        print(f"GPU configuration error: {e}")

def create_grammar_model(vocab_size, max_sequence_length=50):
    """Create a simple model for grammar correction"""
    model = keras.Sequential([
        # Input layer
        layers.Input(shape=(max_sequence_length,)),
        # Embedding layer
        layers.Embedding(vocab_size, 128),
        # Bidirectional LSTM for context understanding
        layers.Bidirectional(layers.LSTM(64, return_sequences=True)),
        # Dense layer for word prediction
        layers.Dense(vocab_size, activation='softmax')
    ])
    return model

def prepare_training_data(nlp, vocab, max_sequence_length=50):
    """Prepare training data from German text corpus"""
    # Load German text corpus (you can use any German text corpus)
    # For example, using spaCy's built-in German examples
    texts = [
        "Der Hund läuft im Park.",
        "Die Katze schläft auf dem Sofa.",
        "Ich gehe zur Schule.",
        "Wir essen zusammen zu Mittag.",
        "Er liest ein interessantes Buch.",
        # Add more German sentences here
    ]
    
    # Convert texts to sequences
    sequences = []
    for text in texts:
        doc = nlp(text)
        sequence = [vocab.get(token.text.lower(), 0) for token in doc]
        # Pad or truncate sequence
        if len(sequence) < max_sequence_length:
            sequence.extend([0] * (max_sequence_length - len(sequence)))
        else:
            sequence = sequence[:max_sequence_length]
        sequences.append(sequence)
    
    return np.array(sequences)

def main():
    print("Loading SpaCy German model...")
    try:
        nlp = spacy.load("de_core_news_lg")
    except OSError:
        print("Downloading German language model...")
        spacy.cli.download("de_core_news_lg")
        nlp = spacy.load("de_core_news_lg")

    # Create vocabulary from SpaCy's vocab
    print("Creating vocabulary...")
    vocab = {}
    # Add special tokens
    vocab["<PAD>"] = 0
    vocab["<UNK>"] = 1
    
    # Add words from SpaCy's vocabulary
    for word in nlp.vocab.strings:
        if word.isalpha():  # Only add words (no punctuation, numbers, etc.)
            vocab[word.lower()] = len(vocab)
    
    # Save vocabulary
    print("Saving vocabulary...")
    os.makedirs("../assets/models", exist_ok=True)
    with open("../assets/models/de_vocab.json", "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)

    # Create and train model
    print("Creating and training model...")
    vocab_size = len(vocab)
    model = create_grammar_model(vocab_size)
    
    # Prepare training data
    X = prepare_training_data(nlp, vocab)
    # For this example, we'll use the same data as both input and target
    y = X.copy()
    
    # Compile model
    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    # Train model (with minimal epochs for this example)
    model.fit(X, y, epochs=10, batch_size=32, verbose=1)
    
    # Convert to TFLite with SELECT_TF_OPS support
    print("Converting to TensorFlow Lite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Enable SELECT_TF_OPS to support LSTM operations
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    
    # Disable experimental tensor list ops lowering
    converter._experimental_lower_tensor_list_ops = False
    
    # Optional optimizations
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    try:
        tflite_model = converter.convert()
        
        # Save TFLite model
        print("Saving TFLite model...")
        with open("../assets/models/de_grammar_model.tflite", "wb") as f:
            f.write(tflite_model)
        
        print("Done! Model and vocabulary have been saved to assets/models/")
        print(f"Vocabulary size: {vocab_size} words")
        print(f"Model size: {len(tflite_model) / (1024*1024):.2f} MB")
        
    except Exception as e:
        print(f"TFLite conversion failed: {e}")
        print("Saving as regular TensorFlow SavedModel instead...")
        model.save("../assets/models/de_grammar_model")
        print("SavedModel saved successfully!")

if __name__ == "__main__":
    main()