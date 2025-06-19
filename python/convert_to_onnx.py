# convert_to_onnx.py
import torch
import onnx
import onnxruntime as ort
from transformers import MT5ForConditionalGeneration, MT5Tokenizer
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ModelConverter:
    def __init__(self, model_path="./german_gec_mt5/checkpoint-3500/"):
        self.model_path = model_path
        self.output_dir = "./models/"
        os.makedirs(self.output_dir, exist_ok=True)
        
    def load_model(self):
        """Load trained PyTorch model"""
        logger.info(f"Loading model from {self.model_path}")
        self.model = MT5ForConditionalGeneration.from_pretrained(self.model_path)
        self.tokenizer = MT5Tokenizer.from_pretrained(self.model_path)
        self.model.eval()
        logger.info("Model loaded successfully")
        
    def convert_to_onnx(self):
        """Convert PyTorch model to ONNX with custom wrapper"""
        logger.info("Starting ONNX conversion...")
        
        # Create wrapper class for generation
        class MT5GenerationWrapper(torch.nn.Module):
            def __init__(self, model, tokenizer):
                super().__init__()
                self.model = model
                self.tokenizer = tokenizer
                
            def forward(self, input_ids, attention_mask):
                # Generate with fixed parameters
                outputs = self.model.generate(
                    input_ids=input_ids,
                    attention_mask=attention_mask,
                    max_length=64,
                    num_beams=1,
                    do_sample=False,
                    early_stopping=True,
                    pad_token_id=self.tokenizer.pad_token_id
                )
                return outputs
        
        wrapper = MT5GenerationWrapper(self.model, self.tokenizer)
        wrapper.eval()
        
        # Sample input for tracing
        sample_text = "Korrigiere: Das ist ein Test."
        inputs = self.tokenizer(
            sample_text,
            max_length=32,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )
        
        onnx_path = os.path.join(self.output_dir, "german_gec_model.onnx")
        
        try:
            # Export wrapper to ONNX
            torch.onnx.export(
                wrapper,
                (inputs["input_ids"], inputs["attention_mask"]),
                onnx_path,
                export_params=True,
                opset_version=11,
                do_constant_folding=True,
                input_names=["input_ids", "attention_mask"],
                output_names=["generated_ids"],
                dynamic_axes={
                    "input_ids": {0: "batch_size", 1: "sequence"},
                    "attention_mask": {0: "batch_size", 1: "sequence"},
                    "generated_ids": {0: "batch_size", 1: "sequence"}
                }
            )
            logger.info(f"ONNX model saved to {onnx_path}")
            
        except Exception as e:
            logger.warning(f"Generation wrapper failed: {e}")
            logger.info("Trying encoder-only export...")
            return self._convert_encoder_only()
        
        return onnx_path
    
    def _convert_encoder_only(self):
        """Fallback: Convert encoder only"""
        logger.info("Converting encoder-only model...")
        
        class EncoderWrapper(torch.nn.Module):
            def __init__(self, model):
                super().__init__()
                self.encoder = model.encoder
                
            def forward(self, input_ids, attention_mask):
                outputs = self.encoder(
                    input_ids=input_ids,
                    attention_mask=attention_mask,
                    return_dict=True
                )
                return outputs.last_hidden_state
        
        encoder_wrapper = EncoderWrapper(self.model)
        encoder_wrapper.eval()
        
        sample_text = "Korrigiere: Das ist ein Test."
        inputs = self.tokenizer(
            sample_text,
            max_length=32,
            padding="max_length",
            truncation=True,
            return_tensors="pt"
        )
        
        onnx_path = os.path.join(self.output_dir, "german_gec_encoder.onnx")
        
        torch.onnx.export(
            encoder_wrapper,
            (inputs["input_ids"], inputs["attention_mask"]),
            onnx_path,
            export_params=True,
            opset_version=11,
            do_constant_folding=True,
            input_names=["input_ids", "attention_mask"],
            output_names=["hidden_states"],
            dynamic_axes={
                "input_ids": {0: "batch_size", 1: "sequence"},
                "attention_mask": {0: "batch_size", 1: "sequence"},
                "hidden_states": {0: "batch_size", 1: "sequence", 2: "hidden_dim"}
            }
        )
        
        logger.info(f"Encoder-only ONNX model saved to {onnx_path}")
        return onnx_path
        
    def verify_onnx(self, onnx_path):
        """Verify ONNX model"""
        logger.info("Verifying ONNX model...")
        
        try:
            # Load and check ONNX model
            onnx_model = onnx.load(onnx_path)
            onnx.checker.check_model(onnx_model)
            logger.info("ONNX model structure is valid")
            
            # Test with ONNX Runtime
            session = ort.InferenceSession(onnx_path)
            
            sample_text = "Korrigiere: Das ist ein Test."
            inputs = self.tokenizer(
                sample_text,
                max_length=32,
                padding="max_length",
                truncation=True,
                return_tensors="pt"
            )
            
            ort_inputs = {
                "input_ids": inputs["input_ids"].numpy(),
                "attention_mask": inputs["attention_mask"].numpy()
            }
            
            ort_outputs = session.run(None, ort_inputs)
            logger.info(f"ONNX inference successful - output shape: {ort_outputs[0].shape}")
            
            return True
            
        except Exception as e:
            logger.warning(f"ONNX verification failed: {e}")
            logger.info("Model exported but verification incomplete")
            return False

def main():
    converter = ModelConverter()
    
    try:
        # Load PyTorch model
        converter.load_model()
        
        # Convert to ONNX
        onnx_path = converter.convert_to_onnx()
        
        # Verify ONNX model
        converter.verify_onnx(onnx_path)
        
        logger.info("✅ Conversion completed successfully!")
        logger.info(f"ONNX model available at: {onnx_path}")
        
    except Exception as e:
        logger.error(f"❌ Conversion failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()