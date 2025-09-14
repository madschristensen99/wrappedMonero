import { UI_SETTINGS } from '../config/constants.js';

export function showLoading(show) {
  const loadingElement = document.getElementById('loading');
  if (loadingElement) {
    loadingElement.style.display = show ? 'flex' : 'none';
  }
}

export function showError(message) {
  const errorElement = document.getElementById('error');
  const errorTextElement = document.getElementById('errorText');
  
  if (errorElement && errorTextElement) {
    errorTextElement.textContent = message;
    errorElement.style.display = 'flex';
    
    setTimeout(() => {
      if (errorElement) {
        errorElement.style.display = 'none';
      }
    }, UI_SETTINGS.ERROR_TIMEOUT);
  }
}

export function showSuccess(message) {
  const successElement = document.getElementById('success');
  const successTextElement = document.getElementById('successText');
  
  if (successElement && successTextElement) {
    successTextElement.textContent = message;
    successElement.style.display = 'flex';
    
    setTimeout(() => {
      if (successElement) {
        successElement.style.display = 'none';
      }
    }, UI_SETTINGS.SUCCESS_TIMEOUT);
  }
}

export function formatAddress(address) {
  if (!address || address.length < 42) return address;
  return `${address.substring(0, 6)}...${address.substring(38)}`;
}

export function formatAmount(amount, decimals = 18) {
  try {
    return parseFloat(amount).toFixed(6);
  } catch (error) {
    return '0';
  }
}

export function createElement(tag, className = '', content = '') {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (content) element.innerHTML = content;
  return element;
}