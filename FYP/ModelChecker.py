import scipy.io
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import TensorDataset, DataLoader
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import confusion_matrix, classification_report

# ==========================================
# 1. HARDCODED SCALING CONSTANTS (From Training)
# ==========================================
GLOBAL_MAX_CURRENT = 187.98849357328348
GLOBAL_MAX_FFT = 4146.552362875881

# ==========================================
# 2. UPGRADED 1D-CNN MODEL DEFINITION
# ==========================================
# ==========================================
# 2. ORIGINAL 1D-CNN MODEL DEFINITION
# ==========================================
class ArcFaultCNN(nn.Module):
    def __init__(self):
        super(ArcFaultCNN, self).__init__()
        self.conv1 = nn.Conv1d(in_channels=1, out_channels=1, kernel_size=3, stride=1, padding=1)
        self.relu1 = nn.ReLU()
        self.conv2 = nn.Conv1d(in_channels=1, out_channels=1, kernel_size=3, stride=1, padding=1)
        self.relu2 = nn.ReLU()
        self.pool = nn.MaxPool1d(kernel_size=2, stride=2)
        self.fc1 = nn.Linear(in_features=160, out_features=128)
        self.relu3 = nn.ReLU()
        self.fc2 = nn.Linear(in_features=128, out_features=1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        x = self.relu1(self.conv1(x))
        x = self.relu2(self.conv2(x))
        x = self.pool(x)
        x = x.view(x.size(0), -1)
        x = self.relu3(self.fc1(x))
        x = self.sigmoid(self.fc2(x))
        return x

def main():
    # ==========================================
    # 3. LOAD & PREPROCESS LOCAL DATA
    # ==========================================
    # Replace with your actual local test dataset filename
    dataset_filename = r"C:\Users\samir\Desktop\FYP\arc_dataset_check.mat" 
    print(f"Loading {dataset_filename}...")
    
    mat_data = scipy.io.loadmat(dataset_filename)
    X_raw = mat_data['X_data']
    Y_raw = mat_data['Y_data'].ravel()

    # Apply the exact scaling from training
    X_time = X_raw / GLOBAL_MAX_CURRENT

    X_fft = np.abs(np.fft.fft(X_raw, axis=1))
    X_fft[:, 0] = X_fft[:, 0] * 0.1  # Shrink DC spike
    X_fft = X_fft / GLOBAL_MAX_FFT

    # Concatenate features
    X_processed = np.concatenate((X_fft, X_time), axis=1)

    # Convert to Tensors
    X_tensor = torch.tensor(X_processed, dtype=torch.float32).unsqueeze(1)
    y_tensor = torch.tensor(Y_raw, dtype=torch.float32)

    test_loader = DataLoader(TensorDataset(X_tensor, y_tensor), batch_size=32, shuffle=False)

    # ==========================================
    # 4. LOAD MODEL WEIGHTS
    # ==========================================
    print("Loading model weights...")
    model = ArcFaultCNN()
    # Use weights_only=True for safer loading in modern PyTorch versions
    model.load_state_dict(torch.load(r"C:\Users\samir\Desktop\FYP\Generated models 2.0\arc_fault_cnn.pth", weights_only=True))
    model.eval()  # Set to evaluation mode

    # ==========================================
    # 5. INFERENCE & PLOTTING
    # ==========================================
    print("Running inference...")
    all_preds = []
    all_labels = []

    with torch.no_grad():
        for inputs, labels in test_loader:
            outputs = model(inputs)
            predicted = (outputs > 0.5).float()
            
            all_preds.extend(predicted.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())

    all_preds = np.array(all_preds).flatten()
    all_labels = np.array(all_labels).flatten()

    print("\nLocal Validation - Classification Report:")
    print(classification_report(all_labels, all_preds, target_names=['Normal', 'Arc Fault'], zero_division=0))

    # Plot Confusion Matrix
    cm = confusion_matrix(all_labels, all_preds)
    plt.figure(figsize=(6, 5))
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues',
                xticklabels=['Normal (0)', 'Arc Fault (1)'],
                yticklabels=['Normal (0)', 'Arc Fault (1)'])
    plt.ylabel('True Class')
    plt.xlabel('Predicted Class')
    plt.title('1D-CNN: Local Inference Performance')
    plt.show()

if __name__ == '__main__':
    main()